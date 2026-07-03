#!/usr/bin/env bash
#
# AtmoFrance - Phase 4 (partie 2) : consumer Bronze + tests unitaires
# A lancer depuis le dossier atmofrance/ apres setup_phase4.sh
#
set -euo pipefail

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis le dossier atmofrance/"
  exit 1
fi
if [ ! -d .venv ]; then
  echo "ERREUR : lance d'abord setup_phase4.sh (environnement .venv absent)"
  exit 1
fi

echo ">> Phase 4 partie 2 : consumer Bronze + tests"

# ---------------------------------------------------------------------------
# 1. Correction du datetime deprecie dans le producer
# ---------------------------------------------------------------------------
echo ">> Correction datetime dans le producer..."
sed -i 's/^from datetime import datetime$/from datetime import datetime, timezone/' ingestion/producers/geodair_producer.py
sed -i 's/datetime.utcnow().isoformat()/datetime.now(timezone.utc).isoformat()/' ingestion/producers/geodair_producer.py

# ---------------------------------------------------------------------------
# 2. Consumer Bronze
# ---------------------------------------------------------------------------
echo ">> Ecriture de ingestion/consumers/bronze_consumer.py..."
mkdir -p ingestion/consumers
touch ingestion/consumers/__init__.py
cat > ingestion/consumers/bronze_consumer.py << 'PYEOF'
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
PYEOF

# ---------------------------------------------------------------------------
# 3. Tests unitaires
# ---------------------------------------------------------------------------
echo ">> Ecriture des tests unitaires..."
mkdir -p tests/unit
touch tests/__init__.py tests/unit/__init__.py
cat > tests/unit/test_ingestion.py << 'PYEOF'
"""Tests unitaires de l'ingestion : parsing Geod'Air et partitionnement Bronze.

Ces tests ne necessitent ni Kafka ni MinIO : ils valident la logique pure de
transformation, qui est le coeur metier de l'ingestion.
"""
from ingestion import config
from ingestion.consumers.bronze_consumer import _date_partition
from ingestion.producers.geodair_producer import _iterer_mesures


# En-tete reel du flux E2 Geod'Air (23 colonnes)
ENTETE = (
    '"Date de début";"Date de fin";"Organisme";"code zas";"Zas";"code site";'
    '"nom site";"type d\'implantation";"Polluant";"type d\'influence";'
    '"discriminant";"Réglementaire";"type d\'évaluation";"procédure de mesure";'
    '"type de valeur";"valeur";"valeur brute";"unité de mesure";"taux de saisie";'
    '"couverture temporelle";"couverture de données";"code qualité";"validité"'
)


def _ligne(polluant: str, valeur: str, unite: str, validite: str) -> str:
    return (
        f'"2026/07/01 00:00:00";"2026/07/01 01:00:00";"ATMO GRAND EST";'
        f'"FR44ZAG02";"ZAG METZ";"FR01011";"Metz-Centre";"Urbaine";'
        f'"{polluant}";"Fond";"A";"Oui";"mesures fixes";"proc";'
        f'"moyenne horaire brute";"{valeur}";"{valeur}";"{unite}";;;;"A";"{validite}"'
    )


def _csv(*lignes: str) -> str:
    return "\n".join([ENTETE, *lignes])


def test_filtrage_polluants_retenus():
    """Seuls les 6 polluants reglementaires doivent etre conserves."""
    texte = _csv(
        _ligne("NO2", "12.4", "µg-m3", "1"),
        _ligne("NO", "-0.8", "µg-m3", "1"),        # a exclure
        _ligne("NOX as NO2", "20", "µg-m3", "1"),  # a exclure
        _ligne("C6H6", "0.5", "µg-m3", "1"),       # a exclure
        _ligne("O3", "65", "µg-m3", "1"),
    )
    mesures = list(_iterer_mesures(texte))
    codes = {m["code_polluant"] for m in mesures}
    assert len(mesures) == 2
    assert codes == {"NO2", "O3"}


def test_mapping_pm25():
    """Le libelle 'PM2.5' doit etre mappe vers le code interne 'PM25'."""
    texte = _csv(_ligne("PM2.5", "8.2", "µg/m3", "1"))
    mesures = list(_iterer_mesures(texte))
    assert len(mesures) == 1
    assert mesures[0]["code_polluant"] == "PM25"
    assert mesures[0]["polluant_source"] == "PM2.5"


def test_normalisation_unites():
    """Les trois formes d'unites reelles doivent etre normalisees."""
    texte = _csv(
        _ligne("NO2", "12", "µg-m3", "1"),   # -> ug/m3
        _ligne("O3", "65", "µg/m3", "1"),    # -> ug/m3
        _ligne("CO", "0.3", "mg-m3", "4"),   # -> mg/m3
    )
    mesures = {m["code_polluant"]: m["unite"] for m in _iterer_mesures(texte)}
    assert mesures["NO2"] == "ug/m3"
    assert mesures["O3"] == "ug/m3"
    assert mesures["CO"] == "mg/m3"


def test_valeurs_negatives_conservees():
    """Les valeurs negatives (bruit de fond) sont conservees en Bronze
    (le nettoyage est fait plus loin, en Silver)."""
    texte = _csv(_ligne("NO2", "-0.8", "µg-m3", "1"))
    mesures = list(_iterer_mesures(texte))
    assert len(mesures) == 1
    assert mesures[0]["valeur"] == "-0.8"


def test_lineage_present():
    """Chaque mesure doit porter un horodatage d'ingestion (tracabilite)."""
    texte = _csv(_ligne("NO2", "12", "µg-m3", "1"))
    mesure = next(_iterer_mesures(texte))
    assert "_ingested_at" in mesure
    assert mesure["_ingested_at"]


def test_partition_date():
    """Le partitionnement Bronze extrait la date d'evenement au format ISO."""
    assert _date_partition({"date_debut": "2026/07/01 00:00:00"}) == "2026-07-01"
    assert _date_partition({"date_debut": "2026/12/25 14:00:00"}) == "2026-12-25"
    assert _date_partition({}) == "inconnue"
    assert _date_partition({"date_debut": ""}) == "inconnue"


def test_config_six_polluants():
    """Le referentiel doit contenir exactement les 6 polluants reglementaires."""
    assert set(config.POLLUANTS_RETENUS.values()) == {
        "NO2", "O3", "PM10", "PM25", "SO2", "CO"
    }
PYEOF

# ---------------------------------------------------------------------------
# 4. Ajout de pytest aux dependances + installation
# ---------------------------------------------------------------------------
echo ">> Ajout de pytest et installation..."
grep -q "pytest" ingestion/requirements.txt || cat >> ingestion/requirements.txt << 'EOF'

# Tests
pytest==8.2.1
EOF
.venv/bin/pip install --quiet pytest==8.2.1

# ---------------------------------------------------------------------------
# 5. Execution des tests
# ---------------------------------------------------------------------------
echo ""
echo ">> Execution des tests unitaires..."
.venv/bin/python -m pytest tests/unit/test_ingestion.py -v

echo ""
echo "=============================================="
echo " Phase 4 partie 2 installee."
echo "=============================================="
echo " Prochaine etape (ecrire dans Bronze) :"
echo "   source .venv/bin/activate"
echo "   # 1) publier des mesures dans Kafka :"
echo "   python -m ingestion.producers.geodair_producer --date 2026-07-01"
echo "   # 2) les ecrire dans le datalake Bronze :"
echo "   python -m ingestion.consumers.bronze_consumer"
echo "=============================================="
