"""DAG Airflow — orchestration du pipeline AtmoFrance.

Ce DAG enchaine les cinq etapes du pipeline de donnees, de l'ingestion des
mesures Geod'Air jusqu'au chargement des datamarts dans PostgreSQL. Chaque
tache appelle un module Python du projet, execute dans l'environnement virtuel
principal du projet (.venv) via une commande bash. Airflow lui-meme tourne dans
un environnement virtuel separe (.venv-airflow) afin d'eviter tout conflit de
dependances.

Enchainement :
    ingest_geodair → consume_to_bronze → bronze_to_silver
                   → silver_to_gold → gold_to_postgres

Planification : quotidienne. Les mesures Geod'Air etant consolidees une fois
par jour, une execution journaliere suffit a maintenir les datamarts a jour.
"""
from datetime import datetime, timedelta
import os

from airflow import DAG
from airflow.providers.standard.operators.bash import BashOperator

# Racine du projet et environnement virtuel principal.
# AIRFLOW_VAR_PROJECT_DIR peut surcharger le chemin ; sinon valeur par defaut.
PROJET = os.environ.get("ATMOFRANCE_HOME", os.path.expanduser("~/taf/bahut/atmofrance"))
VENV = f"{PROJET}/.venv/bin/python"

# Date du jour au format attendu par le producteur (fichier de la veille,
# les donnees consolidees etant disponibles a J+1).
DATE_TEMPLATE = "{{ macros.ds_add(ds, -1) }}"

arguments_communs = {
    "owner": "atmofrance",
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
}


def cmd(module: str, args: str = "") -> str:
    """Construit une commande bash executant un module dans le venv du projet."""
    return f"cd {PROJET} && {VENV} -m {module} {args}"


with DAG(
    dag_id="atmofrance_pipeline",
    description="Pipeline complet de la qualite de l'air : ingestion, "
                "traitement Medallion et chargement PostgreSQL.",
    default_args=arguments_communs,
    start_date=datetime(2026, 7, 1),
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    tags=["atmofrance", "data-engineering", "medallion"],
) as dag:

    # 1. Ingestion : telecharge le fichier Geod'Air et publie dans Kafka.
    ingest_geodair = BashOperator(
        task_id="ingest_geodair",
        bash_command=cmd(
            "ingestion.producers.geodair_producer",
            f"--date {DATE_TEMPLATE}",
        ),
    )

    # 2. Consommation : lit Kafka et ecrit les mesures brutes en zone Bronze.
    consume_to_bronze = BashOperator(
        task_id="consume_to_bronze",
        bash_command=cmd(
            "ingestion.consumers.bronze_consumer",
            "--timeout 30",
        ),
    )

    # 3. Bronze -> Silver : nettoyage, typage, deduplication (Spark).
    bronze_to_silver = BashOperator(
        task_id="bronze_to_silver",
        bash_command=cmd("processing.spark.bronze_to_silver"),
    )

    # 4. Silver -> Gold : agregations et indice de qualite de l'air (Spark).
    silver_to_gold = BashOperator(
        task_id="silver_to_gold",
        bash_command=cmd("processing.spark.silver_to_gold"),
    )

    # 5. Gold -> PostgreSQL : chargement des datamarts (Spark JDBC).
    gold_to_postgres = BashOperator(
        task_id="gold_to_postgres",
        bash_command=cmd("processing.spark.gold_to_postgres"),
    )

    # Enchainement lineaire des taches.
    ingest_geodair >> consume_to_bronze >> bronze_to_silver >> silver_to_gold >> gold_to_postgres
