"""Connexions aux bases de donnees du projet AtmoFrance."""
import psycopg
from pymongo import MongoClient

from ingestion import config


def connexion_postgres():
    return psycopg.connect(
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
