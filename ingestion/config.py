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
