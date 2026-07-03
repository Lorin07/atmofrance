#!/usr/bin/env bash
#
# AtmoFrance - Phase 7 : chargement des datamarts Gold dans PostgreSQL (Spark JDBC)
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

echo ">> Phase 7 : chargement Gold -> PostgreSQL"

# ---------------------------------------------------------------------------
# 1. Ecrire le schema Gold + le driver dans spark_utils + le job
# ---------------------------------------------------------------------------
echo ">> Ecriture du schema Gold (infra/postgres/init/02_gold.sql)..."
cat > infra/postgres/init/02_gold.sql << 'SQLEOF'
-- AtmoFrance - Tables Gold chargees par Spark pour l'API et le dashboard.
CREATE TABLE IF NOT EXISTS gold_indice_journalier (
    id             BIGSERIAL PRIMARY KEY,
    code_site      VARCHAR(20),
    nom_site       VARCHAR(200),
    jour           DATE,
    indice_atmo    SMALLINT,
    qualificatif   VARCHAR(40),
    polluant_resp  VARCHAR(10),
    latitude       DOUBLE PRECISION,
    longitude      DOUBLE PRECISION,
    geom           GEOMETRY(Point, 4326),
    UNIQUE (code_site, jour)
);
CREATE INDEX IF NOT EXISTS idx_gold_indice_jour ON gold_indice_journalier (jour);
CREATE INDEX IF NOT EXISTS idx_gold_indice_geom ON gold_indice_journalier USING GIST (geom);

CREATE TABLE IF NOT EXISTS gold_moyennes_journalieres (
    id             BIGSERIAL PRIMARY KEY,
    code_site      VARCHAR(20),
    nom_site       VARCHAR(200),
    code_polluant  VARCHAR(10),
    jour           DATE,
    moyenne        DOUBLE PRECISION,
    minimum        DOUBLE PRECISION,
    maximum        DOUBLE PRECISION,
    nb_mesures     INTEGER,
    unite          VARCHAR(20),
    UNIQUE (code_site, code_polluant, jour)
);
CREATE INDEX IF NOT EXISTS idx_gold_moy_jour ON gold_moyennes_journalieres (jour);
CREATE INDEX IF NOT EXISTS idx_gold_moy_pol ON gold_moyennes_journalieres (code_polluant);

CREATE TABLE IF NOT EXISTS gold_depassements (
    id             BIGSERIAL PRIMARY KEY,
    code_site      VARCHAR(20),
    nom_site       VARCHAR(200),
    code_polluant  VARCHAR(10),
    horodatage     TIMESTAMPTZ,
    jour           DATE,
    valeur         DOUBLE PRECISION,
    unite          VARCHAR(20),
    depassement    VARCHAR(10)
);
CREATE INDEX IF NOT EXISTS idx_gold_dep_jour ON gold_depassements (jour);
CREATE INDEX IF NOT EXISTS idx_gold_dep_niveau ON gold_depassements (depassement);
SQLEOF

# ---------------------------------------------------------------------------
# 2. Appliquer le schema Gold au Postgres deja en cours (idempotent)
# ---------------------------------------------------------------------------
echo ">> Application du schema Gold a la base en cours..."
docker compose exec -T postgres psql -U atmo -d atmofrance < infra/postgres/init/02_gold.sql
echo "   Tables Gold creees."

# ---------------------------------------------------------------------------
# 3. Mettre a jour spark_utils.py (ajout driver JDBC + fonction jdbc_postgres)
# ---------------------------------------------------------------------------
echo ">> Mise a jour de processing/spark/spark_utils.py..."
cat > processing/spark/spark_utils.py << 'PYEOF'
"""Utilitaires Spark partages par les jobs de traitement."""
from pyspark.sql import SparkSession

from ingestion import config

_HADOOP_AWS = "org.apache.hadoop:hadoop-aws:3.3.4"
_AWS_SDK = "com.amazonaws:aws-java-sdk-bundle:1.12.262"
_POSTGRES_JDBC = "org.postgresql:postgresql:42.7.3"


def creer_spark_local(nom: str) -> SparkSession:
    return (
        SparkSession.builder
        .appName(nom)
        .master("local[*]")
        .config("spark.sql.shuffle.partitions", "8")
        .config("spark.ui.showConsoleProgress", "false")
        .getOrCreate()
    )


def creer_spark_minio(nom: str) -> SparkSession:
    endpoint = config.MINIO_ENDPOINT
    if not endpoint.startswith("http"):
        endpoint = f"http://{endpoint}"
    return (
        SparkSession.builder
        .appName(nom)
        .master("local[*]")
        .config("spark.jars.packages", f"{_HADOOP_AWS},{_AWS_SDK},{_POSTGRES_JDBC}")
        .config("spark.hadoop.fs.s3a.endpoint", endpoint)
        .config("spark.hadoop.fs.s3a.access.key", config.MINIO_ACCESS_KEY)
        .config("spark.hadoop.fs.s3a.secret.key", config.MINIO_SECRET_KEY)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        .config("spark.sql.shuffle.partitions", "8")
        .config("spark.ui.showConsoleProgress", "false")
        .getOrCreate()
    )


def jdbc_postgres() -> dict:
    hote = config._get("POSTGRES_HOST_LOCAL", "localhost")
    port = config._get("POSTGRES_PORT", "5432")
    base = config._get("POSTGRES_DB", "atmofrance")
    url = f"jdbc:postgresql://{hote}:{port}/{base}"
    proprietes = {
        "user": config._get("POSTGRES_USER", "atmo"),
        "password": config._get("POSTGRES_PASSWORD", "change_me"),
        "driver": "org.postgresql.Driver",
    }
    return {"url": url, "properties": proprietes}


def s3_path(bucket: str, prefixe: str = "") -> str:
    base = f"s3a://{bucket}"
    return f"{base}/{prefixe}" if prefixe else base
PYEOF

# ---------------------------------------------------------------------------
# 4. Ecrire le job gold_to_postgres.py
# ---------------------------------------------------------------------------
echo ">> Ecriture de processing/spark/gold_to_postgres.py..."
cat > processing/spark/gold_to_postgres.py << 'PYEOF'
"""Job Spark : chargement des datamarts Gold dans PostgreSQL via JDBC.

Usage :
    python -m processing.spark.gold_to_postgres
"""
from pyspark.sql import functions as F

from processing.spark import spark_utils


def _lire_stations_jdbc(spark, jdbc):
    return (spark.read
            .jdbc(jdbc["url"], "station", properties=jdbc["properties"])
            .select(
                F.col("code_station").alias("code_site"),
                "latitude", "longitude",
            ))


def _ecrire_jdbc(df, jdbc, table: str) -> None:
    (df.write
     .mode("overwrite")
     .option("truncate", "true")
     .jdbc(jdbc["url"], table, properties=jdbc["properties"]))


def charger_gold(spark) -> None:
    jdbc = spark_utils.jdbc_postgres()
    gold = spark_utils.s3_path("gold")

    stations = _lire_stations_jdbc(spark, jdbc)

    indice = spark.read.parquet(f"{gold}/indice_journalier")
    indice = (indice
              .withColumnRenamed("date_mesure", "jour")
              .join(stations, on="code_site", how="left")
              .select("code_site", "nom_site", "jour", "indice_atmo",
                      "qualificatif", "polluant_resp", "latitude", "longitude"))
    _ecrire_jdbc(indice, jdbc, "gold_indice_journalier")
    print(f"gold_indice_journalier : {indice.count()} lignes chargees")

    moyennes = spark.read.parquet(f"{gold}/moyennes_journalieres")
    moyennes = (moyennes
                .withColumnRenamed("date_mesure", "jour")
                .select("code_site", "nom_site", "code_polluant", "jour",
                        "moyenne", "minimum", "maximum", "nb_mesures", "unite"))
    _ecrire_jdbc(moyennes, jdbc, "gold_moyennes_journalieres")
    print(f"gold_moyennes_journalieres : {moyennes.count()} lignes chargees")

    depassements = spark.read.parquet(f"{gold}/depassements")
    depassements = (depassements
                    .withColumnRenamed("date_mesure", "jour")
                    .select("code_site", "nom_site", "code_polluant",
                            "horodatage", "jour", "valeur", "unite", "depassement"))
    _ecrire_jdbc(depassements, jdbc, "gold_depassements")
    print(f"gold_depassements : {depassements.count()} lignes chargees")


def main() -> None:
    spark = spark_utils.creer_spark_minio("gold-to-postgres")
    charger_gold(spark)
    spark.stop()
    print("\nDatamarts Gold charges dans PostgreSQL avec succes.")


if __name__ == "__main__":
    main()
PYEOF

# ---------------------------------------------------------------------------
# 5. Lancer le chargement Spark
# ---------------------------------------------------------------------------
echo ""
echo ">> Chargement des datamarts Gold dans PostgreSQL (Spark JDBC)..."
echo "   (le driver JDBC PostgreSQL se telecharge au premier lancement)"
.venv/bin/python -m processing.spark.gold_to_postgres

# ---------------------------------------------------------------------------
# 6. Construire les geometries PostGIS a partir de lat/lon
#    (Spark JDBC ecrit lat/lon mais pas le type geometry natif)
# ---------------------------------------------------------------------------
echo ""
echo ">> Construction des geometries PostGIS (indice journalier)..."
docker compose exec -T postgres psql -U atmo -d atmofrance -c "
UPDATE gold_indice_journalier
SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
WHERE longitude IS NOT NULL AND latitude IS NOT NULL AND geom IS NULL;
"

echo ""
echo "=============================================="
echo " Phase 7 terminee."
echo "=============================================="
echo " Verifie le chargement :"
echo "   docker compose exec postgres psql -U atmo -d atmofrance -c \\"
echo "     \"SELECT qualificatif, COUNT(*) FROM gold_indice_journalier GROUP BY qualificatif;\""
echo "=============================================="
