#!/usr/bin/env bash
#
# AtmoFrance - Phase 4 : ingestion streaming (producer Kafka)
# A lancer depuis le dossier atmofrance/ (ou le socle tourne deja).
#
set -euo pipefail

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis le dossier atmofrance/"
  exit 1
fi

echo ">> Phase 4 : mise en place de l'ingestion streaming"

# ---------------------------------------------------------------------------
# 1. Completer le .env avec les acces depuis l'hote (Kafka 29092, MinIO 9000)
# ---------------------------------------------------------------------------
add_var() {
  local key="$1" val="$2"
  if ! grep -q "^${key}=" .env 2>/dev/null; then
    echo "${key}=${val}" >> .env
    echo "   + ${key} ajoute au .env"
  fi
}
echo ">> Complement du .env (acces hote)..."
add_var "KAFKA_BOOTSTRAP_SERVERS_HOST" "localhost:29092"
add_var "MINIO_ENDPOINT_HOST" "localhost:9000"
add_var "GEODAIR_FILES_BASE" "https://files.data.gouv.fr/ineris/lcsqa/concentrations-de-polluants-atmospheriques-reglementes/temps-reel"

# Idem pour .env.example (documentation)
for f in .env.example; do
  grep -q "KAFKA_BOOTSTRAP_SERVERS_HOST" "$f" || cat >> "$f" << 'EOF'

# Acces depuis l'hote (code Python execute hors conteneur)
KAFKA_BOOTSTRAP_SERVERS_HOST=localhost:29092
MINIO_ENDPOINT_HOST=localhost:9000
GEODAIR_FILES_BASE=https://files.data.gouv.fr/ineris/lcsqa/concentrations-de-polluants-atmospheriques-reglementes/temps-reel
EOF
done

# ---------------------------------------------------------------------------
# 2. Fichier config.py (ingestion)
# ---------------------------------------------------------------------------
echo ">> Ecriture de ingestion/config.py..."
mkdir -p ingestion/producers
touch ingestion/__init__.py ingestion/producers/__init__.py
cat > ingestion/config.py << 'PYEOF'
"""Configuration centralisee du projet AtmoFrance.

Charge les parametres depuis les variables d'environnement (.env) et expose
des constantes utilisees par l'ingestion, le traitement et l'API.
"""
import os
from pathlib import Path

from dotenv import load_dotenv

# Charge le .env a la racine du projet
_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(_ROOT / ".env")


def _get(key: str, default: str = "") -> str:
    return os.environ.get(key, default)


# --- Kafka ---------------------------------------------------------------
# Depuis l'hote, Kafka est joignable sur le port 29092 (listener PLAINTEXT_HOST).
# Depuis un conteneur du meme reseau, ce serait kafka:9092.
KAFKA_BOOTSTRAP_SERVERS = _get("KAFKA_BOOTSTRAP_SERVERS_HOST", "localhost:29092")
KAFKA_TOPIC_AIR = _get("KAFKA_TOPIC_AIR", "air-raw")
KAFKA_TOPIC_METEO = _get("KAFKA_TOPIC_METEO", "meteo-raw")

# --- MinIO / datalake ----------------------------------------------------
# Depuis l'hote, MinIO est sur localhost:9000.
MINIO_ENDPOINT = _get("MINIO_ENDPOINT_HOST", "localhost:9000")
MINIO_ACCESS_KEY = _get("MINIO_ROOT_USER", "atmo")
MINIO_SECRET_KEY = _get("MINIO_ROOT_PASSWORD", "change_me_minio")
MINIO_BUCKET_BRONZE = _get("MINIO_BUCKET_BRONZE", "bronze")
MINIO_BUCKET_SILVER = _get("MINIO_BUCKET_SILVER", "silver")
MINIO_BUCKET_GOLD = _get("MINIO_BUCKET_GOLD", "gold")

# --- Sources externes ----------------------------------------------------
GEODAIR_FILES_BASE = _get(
    "GEODAIR_FILES_BASE",
    "https://files.data.gouv.fr/ineris/lcsqa/"
    "concentrations-de-polluants-atmospheriques-reglementes/temps-reel",
)

# --- Referentiel metier --------------------------------------------------
# Les 6 polluants reglementaires que le projet conserve.
# Cle = libelle dans le fichier Geod'Air, valeur = code interne (schema SQL).
POLLUANTS_RETENUS = {
    "NO2": "NO2",
    "O3": "O3",
    "PM10": "PM10",
    "PM2.5": "PM25",   # normalisation du point vers notre code
    "SO2": "SO2",
    "CO": "CO",
}

# Normalisation des unites rencontrees dans le fichier reel.
UNITES_NORM = {
    "µg-m3": "ug/m3",
    "µg/m3": "ug/m3",
    "mg-m3": "mg/m3",
}
PYEOF

# ---------------------------------------------------------------------------
# 3. Producer geodair_producer.py
# ---------------------------------------------------------------------------
echo ">> Ecriture de ingestion/producers/geodair_producer.py..."
cat > ingestion/producers/geodair_producer.py << 'PYEOF'
"""Producteur de flux : lit un fichier de mesures Geod'Air (flux E2) et publie
chaque mesure dans le topic Kafka `air-raw`.

Le fichier source est un CSV point-virgule, encode UTF-8 avec BOM, dont le
format a ete etabli par inspection des donnees reelles :

    "Date de debut";"Date de fin";"Organisme";"code zas";"Zas";"code site";
    "nom site";"type d'implantation";"Polluant";"type d'influence";...;
    "valeur";"valeur brute";"unite de mesure";...;"code qualite";"validite"

Seuls les 6 polluants reglementaires sont conserves. Les mesures sont envoyees
telles quelles (donnees brutes) : le nettoyage est fait plus loin, en Silver.

Usage :
    python -m ingestion.producers.geodair_producer --date 2026-07-01
    python -m ingestion.producers.geodair_producer --file chemin/vers/fichier.csv
    python -m ingestion.producers.geodair_producer --date 2026-07-01 --rate 200
"""
import argparse
import csv
import io
import json
import sys
import time
import urllib.request
from datetime import datetime

from kafka import KafkaProducer

from ingestion import config


def _telecharger_csv(date_str: str) -> str:
    """Recupere le fichier journalier Geod'Air pour une date donnee (YYYY-MM-DD)."""
    annee = date_str[:4]
    url = f"{config.GEODAIR_FILES_BASE}/{annee}/FR_E2_{date_str}.csv"
    print(f"Telechargement : {url}")
    with urllib.request.urlopen(url, timeout=60) as reponse:
        contenu = reponse.read()
    # Decodage UTF-8 en retirant le BOM eventuel
    return contenu.decode("utf-8-sig")


def _lire_csv_local(chemin: str) -> str:
    with open(chemin, "r", encoding="utf-8-sig") as f:
        return f.read()


def _iterer_mesures(texte_csv: str):
    """Genere les mesures retenues a partir du contenu CSV.

    Chaque mesure est un dictionnaire pret a etre serialise en JSON.
    Les lignes dont le polluant n'est pas dans le perimetre sont ignorees.
    """
    lecteur = csv.DictReader(io.StringIO(texte_csv), delimiter=";")
    for ligne in lecteur:
        polluant_source = (ligne.get("Polluant") or "").strip()
        if polluant_source not in config.POLLUANTS_RETENUS:
            continue

        unite_source = (ligne.get("unité de mesure") or "").strip()
        yield {
            "date_debut": (ligne.get("Date de début") or "").strip(),
            "date_fin": (ligne.get("Date de fin") or "").strip(),
            "organisme": (ligne.get("Organisme") or "").strip(),
            "code_zas": (ligne.get("code zas") or "").strip(),
            "zas": (ligne.get("Zas") or "").strip(),
            "code_site": (ligne.get("code site") or "").strip(),
            "nom_site": (ligne.get("nom site") or "").strip(),
            "type_implantation": (ligne.get("type d'implantation") or "").strip(),
            "polluant_source": polluant_source,
            "code_polluant": config.POLLUANTS_RETENUS[polluant_source],
            "type_influence": (ligne.get("type d'influence") or "").strip(),
            "type_valeur": (ligne.get("type de valeur") or "").strip(),
            "valeur": (ligne.get("valeur") or "").strip(),
            "valeur_brute": (ligne.get("valeur brute") or "").strip(),
            "unite_source": unite_source,
            "unite": config.UNITES_NORM.get(unite_source, unite_source),
            "code_qualite": (ligne.get("code qualité") or "").strip(),
            "validite": (ligne.get("validité") or "").strip(),
            # Metadonnees de lineage (tracabilite)
            "_ingested_at": datetime.utcnow().isoformat(),
        }


def _creer_producer() -> KafkaProducer:
    return KafkaProducer(
        bootstrap_servers=config.KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
        key_serializer=lambda k: k.encode("utf-8") if k else None,
        acks="all",           # garantie d'ecriture cote broker
        retries=3,
        linger_ms=50,         # petit buffer pour ameliorer le debit
    )


def produire(date_str, chemin, rate: int) -> None:
    """Publie les mesures dans Kafka.

    rate : nombre maximum de messages par seconde (0 = aucune limite).
    """
    if chemin:
        print(f"Lecture du fichier local : {chemin}")
        texte = _lire_csv_local(chemin)
    elif date_str:
        texte = _telecharger_csv(date_str)
    else:
        print("Erreur : preciser --date ou --file", file=sys.stderr)
        sys.exit(1)

    producer = _creer_producer()
    topic = config.KAFKA_TOPIC_AIR

    envoyes = 0
    debut = time.monotonic()
    intervalle = 1.0 / rate if rate > 0 else 0.0

    for mesure in _iterer_mesures(texte):
        # La cle Kafka = code site + polluant, pour regrouper une meme serie
        cle = f"{mesure['code_site']}|{mesure['code_polluant']}"
        producer.send(topic, key=cle, value=mesure)
        envoyes += 1

        if envoyes % 5000 == 0:
            print(f"  {envoyes} mesures envoyees...")

        if intervalle:
            time.sleep(intervalle)

    producer.flush()
    producer.close()

    duree = time.monotonic() - debut
    print(
        f"\nTermine. {envoyes} mesures publiees dans le topic '{topic}' "
        f"en {duree:.1f}s."
    )


def main() -> None:
    parseur = argparse.ArgumentParser(description="Producteur Geod'Air vers Kafka")
    groupe = parseur.add_mutually_exclusive_group(required=True)
    groupe.add_argument("--date", help="Date du fichier a ingerer (YYYY-MM-DD)")
    groupe.add_argument("--file", help="Chemin d'un fichier CSV local")
    parseur.add_argument(
        "--rate",
        type=int,
        default=0,
        help="Debit max en messages/seconde (0 = illimite). "
        "Utiliser une valeur (ex. 200) pour simuler un flux temps reel visible.",
    )
    args = parseur.parse_args()
    produire(args.date, args.file, args.rate)


if __name__ == "__main__":
    main()
PYEOF

# ---------------------------------------------------------------------------
# 4. requirements.txt (ingestion)
# ---------------------------------------------------------------------------
echo ">> Ecriture de ingestion/requirements.txt..."
cat > ingestion/requirements.txt << 'EOF'
# Ingestion AtmoFrance
# kafka-python-ng : fork maintenu compatible Python 3.12+ (API identique a kafka-python)
kafka-python-ng==2.2.3
python-dotenv==1.0.1
minio==7.2.7
EOF

# ---------------------------------------------------------------------------
# 5. Environnement virtuel Python + dependances
# ---------------------------------------------------------------------------
echo ">> Creation de l'environnement virtuel Python..."
if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r ingestion/requirements.txt
echo "   Dependances installees dans .venv"

echo ""
echo "=============================================="
echo " Phase 4 installee."
echo "=============================================="
echo " Prochaine etape (test du producer) :"
echo "   source .venv/bin/activate"
echo "   python -m ingestion.producers.geodair_producer --date 2026-07-01 --rate 500"
echo "=============================================="
