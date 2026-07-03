#!/usr/bin/env bash
#
# AtmoFrance - Phase 6 : referentiel stations (geocodage + PostGIS + MongoDB)
# A lancer depuis le dossier atmofrance/ apres les phases precedentes.
#
set -euo pipefail

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis le dossier atmofrance/"
  exit 1
fi
if [ ! -d .venv ]; then
  echo "ERREUR : environnement .venv absent (lance d'abord setup_phase4.sh)"
  exit 1
fi

echo ">> Phase 6 : referentiel stations"

# ---------------------------------------------------------------------------
# 1. Completer le .env (acces bases depuis l'hote)
# ---------------------------------------------------------------------------
add_var() {
  local key="$1" val="$2"
  if ! grep -q "^${key}=" .env 2>/dev/null; then
    echo "${key}=${val}" >> .env
    echo "   + ${key} ajoute au .env"
  fi
}
echo ">> Complement du .env..."
add_var "POSTGRES_HOST_LOCAL" "localhost"
add_var "MONGO_HOST_LOCAL" "localhost"

# ---------------------------------------------------------------------------
# 2. Module de geocodage
# ---------------------------------------------------------------------------
echo ">> Ecriture de ingestion/geocoding.py..."
cat > ingestion/geocoding.py << 'PYEOF'
"""Geocodage des stations de mesure via l'API adresse.data.gouv.fr.

Le fichier de mesures Geod'Air ne contient pas les coordonnees des stations.
On les reconstruit en extrayant la commune du nom de station puis en la
geocodant via l'API officielle (Base Adresse Nationale), gratuite et sans cle.
"""
import time
import urllib.parse
import urllib.request
import json
import re as _re

API_ADRESSE = "https://api-adresse.data.gouv.fr/search/"

PARASITES = {
    "periurbaine", "periurb", "urbain", "urbaine", "rurale", "trafic",
    "stade", "mairie", "zi", "za", "rocade", "sud", "nord", "est", "ouest",
    "boulevards", "centre", "peripherique", "autoroute", "zone", "parc",
}

_MOTIF_NON_COMMUNE = _re.compile(r"^(a\d+|n\d+|d\d+|rd\d+|zi|za)$", _re.IGNORECASE)

PREFIXES_COMPOSES = {"st", "saint", "sainte", "ste", "le", "la", "les", "aix"}


def _nettoyer_zas(zas: str) -> str:
    nom = zas
    for prefixe in ("ZAG", "ZAR", "ZA "):
        nom = nom.replace(prefixe, "")
    return nom.strip().title()


def extraire_commune(nom_site: str, zas: str) -> str:
    """Extrait une commune candidate depuis le nom de station."""
    nom = nom_site.replace("_", " ").replace("-", " ")
    mots = [m for m in nom.split() if m]
    if not mots:
        return _nettoyer_zas(zas)

    premier = mots[0]
    if _MOTIF_NON_COMMUNE.match(premier) or premier.lower() in PARASITES:
        return _nettoyer_zas(zas)

    if premier.lower() in PREFIXES_COMPOSES and len(mots) > 1:
        composee = [premier]
        for mot in mots[1:]:
            if mot.lower() in PARASITES:
                break
            composee.append(mot)
        return " ".join(composee)

    return premier


def geocoder_commune(commune: str):
    """Retourne (longitude, latitude, label, contexte) ou None."""
    params = urllib.parse.urlencode({"q": commune, "type": "municipality", "limit": 1})
    url = f"{API_ADRESSE}?{params}"
    try:
        with urllib.request.urlopen(url, timeout=15) as reponse:
            data = json.loads(reponse.read().decode("utf-8"))
    except Exception:
        return None
    features = data.get("features", [])
    if not features:
        return None
    coords = features[0]["geometry"]["coordinates"]
    label = features[0]["properties"].get("label", commune)
    contexte = features[0]["properties"].get("context", "")
    return (coords[0], coords[1], label, contexte)


class GeocodeurStations:
    """Geocode un ensemble de stations avec cache par commune."""

    def __init__(self, delai: float = 0.05):
        self._cache = {}
        self._delai = delai

    def geocoder(self, nom_site: str, zas: str) -> dict:
        commune = extraire_commune(nom_site, zas)
        cle = commune.lower()
        if cle not in self._cache:
            resultat = geocoder_commune(commune)
            self._cache[cle] = resultat
            if self._delai:
                time.sleep(self._delai)
        resultat = self._cache[cle]
        if resultat:
            lon, lat, label, contexte = resultat
            return {
                "commune_extraite": commune, "commune_label": label,
                "contexte": contexte, "longitude": lon, "latitude": lat,
                "geocode_ok": True,
            }
        return {
            "commune_extraite": commune, "commune_label": None,
            "contexte": None, "longitude": None, "latitude": None,
            "geocode_ok": False,
        }

    @property
    def nb_communes_geocodees(self) -> int:
        return sum(1 for v in self._cache.values() if v)

    @property
    def nb_communes_total(self) -> int:
        return len(self._cache)
PYEOF

# ---------------------------------------------------------------------------
# 3. Module de connexion aux bases
# ---------------------------------------------------------------------------
echo ">> Ecriture de ingestion/db.py..."
cat > ingestion/db.py << 'PYEOF'
"""Connexions aux bases de donnees du projet AtmoFrance."""
import psycopg2
from pymongo import MongoClient

from ingestion import config


def connexion_postgres():
    return psycopg2.connect(
        host=config._get("POSTGRES_HOST_LOCAL", "localhost"),
        port=config._get("POSTGRES_PORT", "5432"),
        dbname=config._get("POSTGRES_DB", "atmofrance"),
        user=config._get("POSTGRES_USER", "atmo"),
        password=config._get("POSTGRES_PASSWORD", "change_me"),
    )


def client_mongo() -> MongoClient:
    hote = config._get("MONGO_HOST_LOCAL", "localhost")
    port = config._get("MONGO_PORT", "27017")
    user = config._get("MONGO_USER", "atmo")
    mdp = config._get("MONGO_PASSWORD", "change_me")
    uri = f"mongodb://{user}:{mdp}@{hote}:{port}/"
    return MongoClient(uri)


def base_mongo():
    client = client_mongo()
    nom_base = config._get("MONGO_DB", "atmofrance_raw")
    return client, client[nom_base]
PYEOF

# ---------------------------------------------------------------------------
# 4. Script de chargement du referentiel
# ---------------------------------------------------------------------------
echo ">> Ecriture de ingestion/load_stations.py..."
cat > ingestion/load_stations.py << 'PYEOF'
"""Construction et chargement du referentiel des stations de mesure.

  1. lecture des stations distinctes depuis la zone Silver (Spark / MinIO)
  2. geocodage de chaque commune via l'API adresse.data.gouv.fr (avec cache)
  3. ecriture dans PostgreSQL/PostGIS (table station, geometrie)
  4. ecriture des documents bruts dans MongoDB (collection stations)

Usage :
    python -m ingestion.load_stations
"""
from ingestion import db
from ingestion.geocoding import GeocodeurStations
from processing.spark import spark_utils


def lire_stations_silver() -> list:
    spark = spark_utils.creer_spark_minio("load-stations")
    silver = spark.read.parquet(spark_utils.s3_path("silver", "air"))
    stations = (silver
                .select("code_site", "nom_site", "organisme",
                        "code_zas", "zas", "type_implantation", "type_influence")
                .dropDuplicates(["code_site"])
                .orderBy("code_site")
                .collect())
    spark.stop()
    return [row.asDict() for row in stations]


def enrichir_geocodage(stations: list) -> list:
    geocodeur = GeocodeurStations()
    enrichies = []
    for i, st in enumerate(stations, 1):
        geo = geocodeur.geocoder(st["nom_site"], st["zas"] or "")
        st.update(geo)
        enrichies.append(st)
        if i % 50 == 0:
            print(f"  {i}/{len(stations)} stations geocodees "
                  f"({geocodeur.nb_communes_geocodees} communes distinctes)")
    print(f"\nGeocodage termine : "
          f"{geocodeur.nb_communes_geocodees}/{geocodeur.nb_communes_total} "
          f"communes distinctes localisees.")
    nb_ok = sum(1 for s in enrichies if s["geocode_ok"])
    print(f"Stations localisees : {nb_ok}/{len(enrichies)} "
          f"({100 * nb_ok // len(enrichies)}%).")
    return enrichies


def charger_postgres(stations: list) -> None:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    inseres = 0
    for st in stations:
        lon = st.get("longitude")
        lat = st.get("latitude")
        geom_sql = ("ST_SetSRID(ST_MakePoint(%s, %s), 4326)"
                    if lon is not None and lat is not None else "NULL")
        params = [st["code_site"], st["nom_site"], st.get("type_implantation"),
                  st.get("type_influence"), lat, lon]
        params_geom = [lon, lat] if lon is not None and lat is not None else []
        cur.execute(
            f"""
            INSERT INTO station
                (code_station, nom, type_station, type_influence,
                 latitude, longitude, geom)
            VALUES (%s, %s, %s, %s, %s, %s, {geom_sql})
            ON CONFLICT (code_station) DO UPDATE SET
                nom = EXCLUDED.nom,
                type_station = EXCLUDED.type_station,
                type_influence = EXCLUDED.type_influence,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                geom = EXCLUDED.geom
            """,
            params + params_geom,
        )
        inseres += 1
    conn.commit()
    cur.close()
    conn.close()
    print(f"PostgreSQL : {inseres} stations chargees dans la table 'station'.")


def charger_mongo(stations: list) -> None:
    client, base = db.base_mongo()
    collection = base["stations"]
    collection.delete_many({})
    documents = []
    for st in stations:
        doc = dict(st)
        doc["_id"] = st["code_site"]
        documents.append(doc)
    if documents:
        collection.insert_many(documents)
    print(f"MongoDB : {len(documents)} documents stations dans la collection 'stations'.")
    client.close()


def main() -> None:
    print("1. Lecture des stations depuis Silver...")
    stations = lire_stations_silver()
    print(f"   {len(stations)} stations distinctes trouvees.\n")
    print("2. Geocodage des communes...")
    stations = enrichir_geocodage(stations)
    print("\n3. Chargement dans PostgreSQL/PostGIS...")
    charger_postgres(stations)
    print("\n4. Chargement dans MongoDB...")
    charger_mongo(stations)
    print("\nReferentiel stations construit avec succes.")


if __name__ == "__main__":
    main()
PYEOF

# ---------------------------------------------------------------------------
# 5. Tests de geocodage
# ---------------------------------------------------------------------------
echo ">> Ecriture des tests de geocodage..."
cat > tests/unit/test_geocoding.py << 'PYEOF'
"""Tests de l'extraction de commune depuis les noms de station (sans reseau)."""
from ingestion.geocoding import extraire_commune


def test_commune_simple():
    assert extraire_commune("CARPENTRAS", "ZAG AVIGNON") == "CARPENTRAS"
    assert extraire_commune("ANGLET", "ZAG BAYONNE") == "ANGLET"


def test_commune_avec_lieu_dit():
    assert extraire_commune("Roubaix Serres", "ZAG LILLE") == "Roubaix"
    assert extraire_commune("Grenoble Les Frenes", "ZAG GRENOBLE") == "Grenoble"


def test_separateurs():
    assert extraire_commune("Merignac - Magudas", "ZAG BORDEAUX") == "Merignac"
    assert extraire_commune("Bordeaux_GAUTIER", "ZAG BORDEAUX") == "Bordeaux"


def test_code_routier_repli_zas():
    assert extraire_commune("A7 SUD LYONNAIS", "ZAG LYON") == "Lyon"
    assert extraire_commune("N118 Sud", "ZAG PARIS") == "Paris"


def test_zone_industrielle_repli_zas():
    assert extraire_commune("ZI Estuaire Adour", "ZAG BAYONNE") == "Bayonne"


def test_commune_composee():
    assert extraire_commune("St Martin d'Heres", "ZAG GRENOBLE") == "St Martin d'Heres"
    assert extraire_commune("St Denis Stade", "ZAG PARIS") == "St Denis"


def test_nom_vide_repli_zas():
    assert extraire_commune("", "ZAG METZ") == "Metz"
PYEOF

# ---------------------------------------------------------------------------
# 6. Dependances : psycopg2 + pymongo
# ---------------------------------------------------------------------------
echo ">> Ajout de psycopg2-binary et pymongo..."
grep -q "psycopg2" ingestion/requirements.txt 2>/dev/null || cat >> ingestion/requirements.txt << 'EOF'

# Bases de donnees
psycopg2-binary==2.9.9
pymongo==4.7.2
EOF
.venv/bin/pip install --quiet psycopg2-binary==2.9.9 pymongo==4.7.2

# ---------------------------------------------------------------------------
# 7. Tests
# ---------------------------------------------------------------------------
echo ""
echo ">> Execution des tests de geocodage..."
.venv/bin/python -m pytest tests/unit/test_geocoding.py -v

echo ""
echo "=============================================="
echo " Phase 6 installee."
echo "=============================================="
echo " Prochaine etape (construire le referentiel stations) :"
echo "   source .venv/bin/activate"
echo "   python -m ingestion.load_stations"
echo ""
echo " Cela lit les stations du Silver, les geocode via l'API"
echo " adresse.data.gouv.fr, et les charge dans PostGIS + MongoDB."
echo " (~480 stations, quelques dizaines de secondes)"
echo "=============================================="
