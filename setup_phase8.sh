#!/usr/bin/env bash
#
# AtmoFrance - Phase 8 : API REST FastAPI
# A lancer depuis le dossier atmofrance/ apres les phases precedentes.
#
set -euo pipefail

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis le dossier atmofrance/"
  exit 1
fi
if [ ! -d .venv ]; then
  echo "ERREUR : environnement .venv absent"
  exit 1
fi

echo ">> Phase 8 : API REST FastAPI"

mkdir -p api
touch api/__init__.py

# ---------------------------------------------------------------------------
# 1. Module de requetes
# ---------------------------------------------------------------------------
echo ">> Ecriture de api/queries.py..."
cat > api/queries.py << 'PYEOF'
"""Acces aux donnees pour l'API : requetes sur PostgreSQL."""
from ingestion import db


def _lignes_en_dicts(cur) -> list:
    colonnes = [desc[0] for desc in cur.description]
    return [dict(zip(colonnes, ligne)) for ligne in cur.fetchall()]


def lister_stations() -> list:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    cur.execute("""
        SELECT code_station, nom, type_station, type_influence,
               latitude, longitude
        FROM station
        WHERE geom IS NOT NULL
        ORDER BY nom
    """)
    resultat = _lignes_en_dicts(cur)
    conn.close()
    return resultat


def lister_indices(jour=None) -> list:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    if jour:
        cur.execute("""
            SELECT code_site, nom_site, jour, indice_atmo, qualificatif,
                   polluant_resp, latitude, longitude
            FROM gold_indice_journalier
            WHERE geom IS NOT NULL AND jour = %s
            ORDER BY indice_atmo DESC
        """, (jour,))
    else:
        cur.execute("""
            SELECT code_site, nom_site, jour, indice_atmo, qualificatif,
                   polluant_resp, latitude, longitude
            FROM gold_indice_journalier
            WHERE geom IS NOT NULL
            ORDER BY jour DESC, indice_atmo DESC
        """)
    resultat = _lignes_en_dicts(cur)
    conn.close()
    return resultat


def lister_moyennes(polluant=None, jour=None) -> list:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    conditions = []
    params = []
    if polluant:
        conditions.append("code_polluant = %s")
        params.append(polluant)
    if jour:
        conditions.append("jour = %s")
        params.append(jour)
    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
    cur.execute(f"""
        SELECT code_site, nom_site, code_polluant, jour,
               moyenne, minimum, maximum, nb_mesures, unite
        FROM gold_moyennes_journalieres
        {where}
        ORDER BY jour DESC, moyenne DESC
        LIMIT 2000
    """, params)
    resultat = _lignes_en_dicts(cur)
    conn.close()
    return resultat


def lister_depassements(jour=None) -> list:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    if jour:
        cur.execute("""
            SELECT code_site, nom_site, code_polluant, horodatage, jour,
                   valeur, unite, depassement
            FROM gold_depassements
            WHERE jour = %s
            ORDER BY horodatage DESC
        """, (jour,))
    else:
        cur.execute("""
            SELECT code_site, nom_site, code_polluant, horodatage, jour,
                   valeur, unite, depassement
            FROM gold_depassements
            ORDER BY horodatage DESC
            LIMIT 1000
        """)
    resultat = _lignes_en_dicts(cur)
    conn.close()
    return resultat


def statistiques_globales() -> dict:
    conn = db.connexion_postgres()
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) FROM station")
    nb_stations = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM station WHERE geom IS NOT NULL")
    nb_stations_geo = cur.fetchone()[0]
    cur.execute("SELECT COUNT(DISTINCT jour) FROM gold_indice_journalier")
    nb_jours = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM gold_depassements WHERE depassement = 'alerte'")
    nb_alertes = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM gold_depassements WHERE depassement = 'info'")
    nb_info = cur.fetchone()[0]
    cur.execute("""
        SELECT qualificatif, COUNT(*) AS n
        FROM gold_indice_journalier
        GROUP BY qualificatif
        ORDER BY MIN(indice_atmo)
    """)
    repartition = _lignes_en_dicts(cur)

    conn.close()
    return {
        "nb_stations": nb_stations,
        "nb_stations_geolocalisees": nb_stations_geo,
        "nb_jours_donnees": nb_jours,
        "nb_depassements_alerte": nb_alertes,
        "nb_depassements_info": nb_info,
        "repartition_indices": repartition,
    }
PYEOF

# ---------------------------------------------------------------------------
# 2. Application FastAPI
# ---------------------------------------------------------------------------
echo ">> Ecriture de api/main.py..."
cat > api/main.py << 'PYEOF'
"""API REST AtmoFrance.

Lancement :
    uvicorn api.main:app --host 0.0.0.0 --port 8000 --reload
"""
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from api import queries

app = FastAPI(
    title="AtmoFrance API",
    description="API de consultation de la qualite de l'air en France "
                "(mesures Geod'Air, indices ATMO, depassements de seuils).",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", tags=["Accueil"])
def accueil():
    return {
        "service": "AtmoFrance API",
        "version": "1.0.0",
        "ressources": {
            "/health": "Etat de sante de l'API",
            "/stations": "Liste des stations de mesure geolocalisees",
            "/indices": "Indices de qualite de l'air par station",
            "/moyennes": "Moyennes journalieres par polluant",
            "/depassements": "Depassements de seuils reglementaires",
            "/stats": "Statistiques globales",
            "/docs": "Documentation interactive (Swagger)",
        },
    }


@app.get("/health", tags=["Systeme"])
def health():
    try:
        stats = queries.statistiques_globales()
        return {"status": "ok", "base": "accessible",
                "stations": stats["nb_stations"]}
    except Exception as exc:
        return {"status": "degraded", "base": "inaccessible",
                "detail": str(exc)[:200]}


@app.get("/stations", tags=["Donnees"])
def stations():
    resultat = queries.lister_stations()
    return {"count": len(resultat), "stations": resultat}


@app.get("/indices", tags=["Donnees"])
def indices(jour: str | None = Query(None, description="Filtre AAAA-MM-JJ")):
    resultat = queries.lister_indices(jour)
    return {"count": len(resultat), "jour": jour, "indices": resultat}


@app.get("/moyennes", tags=["Donnees"])
def moyennes(
    polluant: str | None = Query(None, description="NO2, O3, PM10, PM25, SO2, CO"),
    jour: str | None = Query(None, description="Filtre AAAA-MM-JJ"),
):
    resultat = queries.lister_moyennes(polluant, jour)
    return {"count": len(resultat), "polluant": polluant, "jour": jour,
            "moyennes": resultat}


@app.get("/depassements", tags=["Donnees"])
def depassements(jour: str | None = Query(None, description="Filtre AAAA-MM-JJ")):
    resultat = queries.lister_depassements(jour)
    return {"count": len(resultat), "jour": jour, "depassements": resultat}


@app.get("/stats", tags=["Donnees"])
def stats():
    return queries.statistiques_globales()
PYEOF

# ---------------------------------------------------------------------------
# 3. Dependances API
# ---------------------------------------------------------------------------
echo ">> Ecriture de api/requirements.txt et installation..."
cat > api/requirements.txt << 'EOF'
# API AtmoFrance
fastapi==0.111.0
uvicorn[standard]==0.30.1
EOF
.venv/bin/pip install --quiet fastapi==0.111.0 "uvicorn[standard]==0.30.1"

# ---------------------------------------------------------------------------
# 4. Amelioration : redemarrage automatique des conteneurs (restart policy)
# ---------------------------------------------------------------------------
echo ">> Ajout du redemarrage automatique des conteneurs..."
if ! grep -q "restart: unless-stopped" docker-compose.yml; then
  # Ajoute 'restart: unless-stopped' apres chaque 'container_name:'
  sed -i '/container_name:/a\    restart: unless-stopped' docker-compose.yml
  echo "   Politique 'restart: unless-stopped' ajoutee. Prochain 'make up' l'appliquera."
else
  echo "   Deja present."
fi

echo ""
echo "=============================================="
echo " Phase 8 terminee."
echo "=============================================="
echo " Lance l'API :"
echo "   source .venv/bin/activate"
echo "   uvicorn api.main:app --host 0.0.0.0 --port 8000"
echo ""
echo " Puis teste dans un navigateur ou un autre terminal :"
echo "   http://localhost:8000/          (accueil)"
echo "   http://localhost:8000/docs      (documentation Swagger)"
echo "   http://localhost:8000/stats     (statistiques)"
echo "=============================================="
