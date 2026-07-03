"""Consommateur de flux : lit le topic Kafka `air-raw` et ecrit les mesures
brutes dans la zone Bronze du datalake (MinIO), au format JSON Lines.

Principe Medallion : la zone Bronze conserve les donnees dans leur etat
d'arrivee, immuables. La conversion en Parquet et le nettoyage interviennent
plus loin, lors du passage Bronze -> Silver (Spark).

Les objets sont partitionnes par date d'evenement :

    bronze/air/date=YYYY-MM-DD/air_<timestamp>_<n>.jsonl

Le consumer accumule les messages par petits lots puis depose un objet par
lot, ce qui evite de creer un objet par message (trop couteux).

Usage :
    python -m ingestion.consumers.bronze_consumer
    python -m ingestion.consumers.bronze_consumer --batch-size 2000 --timeout 30
"""
import argparse
import io
import json
import time
from collections import defaultdict
from datetime import datetime, timezone

from kafka import KafkaConsumer
from minio import Minio

from ingestion import config


def _creer_consumer(timeout_ms: int) -> KafkaConsumer:
    return KafkaConsumer(
        config.KAFKA_TOPIC_AIR,
        bootstrap_servers=config.KAFKA_BOOTSTRAP_SERVERS,
        value_deserializer=lambda v: json.loads(v.decode("utf-8")),
        auto_offset_reset="earliest",     # relire depuis le debut si pas d'offset
        enable_auto_commit=True,
        group_id="bronze-writer",
        consumer_timeout_ms=timeout_ms,   # arrete l'iteration apres inactivite
    )


def _creer_client_minio() -> Minio:
    return Minio(
        config.MINIO_ENDPOINT,
        access_key=config.MINIO_ACCESS_KEY,
        secret_key=config.MINIO_SECRET_KEY,
        secure=False,                     # MinIO local en HTTP
    )


def _date_partition(mesure: dict) -> str:
    """Extrait la date d'evenement (YYYY-MM-DD) depuis 'date_debut' au format
    'YYYY/MM/DD HH:MM:SS'. Retourne 'inconnue' si le champ est absent."""
    date_debut = mesure.get("date_debut", "")
    if len(date_debut) >= 10:
        return date_debut[:10].replace("/", "-")
    return "inconnue"


def _ecrire_lot(client: Minio, bucket: str, partition: str,
                lignes: list, index: int) -> str:
    """Ecrit un lot de mesures comme un objet JSON Lines dans MinIO."""
    contenu = "\n".join(json.dumps(m, ensure_ascii=False) for m in lignes)
    donnees = contenu.encode("utf-8")
    horodatage = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    objet = f"air/date={partition}/air_{horodatage}_{index:05d}.jsonl"
    client.put_object(
        bucket,
        objet,
        data=io.BytesIO(donnees),
        length=len(donnees),
        content_type="application/x-ndjson",
    )
    return objet


def consommer(batch_size: int, timeout: int) -> None:
    consumer = _creer_consumer(timeout_ms=timeout * 1000)
    client = _creer_client_minio()
    bucket = config.MINIO_BUCKET_BRONZE

    # Securite : verifier que le bucket existe
    if not client.bucket_exists(bucket):
        raise RuntimeError(f"Le bucket '{bucket}' n'existe pas dans MinIO.")

    print(f"Ecoute du topic '{config.KAFKA_TOPIC_AIR}' "
          f"(lot={batch_size}, arret apres {timeout}s d'inactivite)...")

    # On accumule les mesures par partition (date d'evenement)
    tampons = defaultdict(list)
    total_ecrit = 0
    objets_ecrits = 0
    compteur_lot = 0

    def vider_partition(partition: str):
        nonlocal total_ecrit, objets_ecrits, compteur_lot
        if not tampons[partition]:
            return
        objet = _ecrire_lot(client, bucket, partition, tampons[partition], compteur_lot)
        total_ecrit += len(tampons[partition])
        objets_ecrits += 1
        compteur_lot += 1
        print(f"  ecrit {len(tampons[partition]):5d} mesures -> {objet}")
        tampons[partition] = []

    debut = time.monotonic()
    for message in consumer:
        mesure = message.value
        partition = _date_partition(mesure)
        tampons[partition].append(mesure)

        # Des qu'une partition atteint la taille de lot, on la vide
        if len(tampons[partition]) >= batch_size:
            vider_partition(partition)

    # Fin d'iteration (timeout) : vider tous les tampons restants
    for partition in list(tampons.keys()):
        vider_partition(partition)

    consumer.close()
    duree = time.monotonic() - debut
    print(f"\nTermine. {total_ecrit} mesures ecrites en Bronze "
          f"({objets_ecrits} objets) en {duree:.1f}s.")


def main() -> None:
    parseur = argparse.ArgumentParser(description="Consumer Kafka -> Bronze (MinIO)")
    parseur.add_argument("--batch-size", type=int, default=2000,
                         help="Nombre de mesures par objet ecrit (defaut 2000)")
    parseur.add_argument("--timeout", type=int, default=20,
                         help="Arret apres N secondes sans nouveau message (defaut 20)")
    args = parseur.parse_args()
    consommer(args.batch_size, args.timeout)


if __name__ == "__main__":
    main()
