#!/usr/bin/env bash
#
# AtmoFrance - Phase 5 : traitement Spark (Bronze -> Silver -> Gold)
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

echo ">> Phase 5 : traitement Spark"

mkdir -p processing/spark
touch processing/__init__.py processing/spark/__init__.py

# ---------------------------------------------------------------------------
# 1. spark_utils.py
# ---------------------------------------------------------------------------
echo ">> Ecriture de processing/spark/spark_utils.py..."
cat > processing/spark/spark_utils.py << 'PYEOF'
"""Utilitaires Spark partages par les jobs de traitement.

Deux modes de session :
  - local  : lit/ecrit sur le systeme de fichiers local (developpement et tests)
  - MinIO  : lit/ecrit sur le datalake via le connecteur S3A (production locale)

Le connecteur S3A permet a Spark de dialoguer avec MinIO exactement comme avec
Amazon S3, ce qui rend le code portable vers le cloud sans modification.
"""
from pyspark.sql import SparkSession

from ingestion import config

# Versions des connecteurs Hadoop/AWS compatibles Spark 3.5.
_HADOOP_AWS = "org.apache.hadoop:hadoop-aws:3.3.4"
_AWS_SDK = "com.amazonaws:aws-java-sdk-bundle:1.12.262"


def creer_spark_local(nom: str) -> SparkSession:
    """Session Spark en mode local, pour le developpement et les tests."""
    return (
        SparkSession.builder
        .appName(nom)
        .master("local[*]")
        .config("spark.sql.shuffle.partitions", "8")
        .config("spark.ui.showConsoleProgress", "false")
        .getOrCreate()
    )


def creer_spark_minio(nom: str) -> SparkSession:
    """Session Spark configuree pour lire/ecrire sur MinIO via S3A."""
    endpoint = config.MINIO_ENDPOINT
    if not endpoint.startswith("http"):
        endpoint = f"http://{endpoint}"

    spark = (
        SparkSession.builder
        .appName(nom)
        .master("local[*]")
        .config("spark.jars.packages", f"{_HADOOP_AWS},{_AWS_SDK}")
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
    return spark


def s3_path(bucket: str, prefixe: str = "") -> str:
    """Construit un chemin s3a:// pour un bucket/prefixe du datalake."""
    base = f"s3a://{bucket}"
    return f"{base}/{prefixe}" if prefixe else base
PYEOF

# ---------------------------------------------------------------------------
# 2. bronze_to_silver.py
# ---------------------------------------------------------------------------
echo ">> Ecriture de processing/spark/bronze_to_silver.py..."
cat > processing/spark/bronze_to_silver.py << 'PYEOF'
"""Job Spark : transformation Bronze -> Silver.

Lit les mesures brutes (JSON Lines) de la zone Bronze, les nettoie et les
type, puis ecrit un jeu Silver en Parquet partitionne par date.

Transformations appliquees :
  - typage explicite de la valeur (chaine -> double)
  - conversion des horodatages (format 'YYYY/MM/DD HH:MM:SS' -> timestamp)
  - deduplication sur la cle evenementielle (site, polluant, horodatage)
  - filtrage des mesures invalides (validite = -1) tout en tracant leur nombre
  - calcul du depassement de seuil reglementaire (info / alerte / aucun)
  - ajout de colonnes de lineage (date de traitement, source)

Usage :
    python -m processing.spark.bronze_to_silver
    python -m processing.spark.bronze_to_silver --date 2026-07-01
"""
import argparse

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import DoubleType

from processing.spark import spark_utils

# Seuils reglementaires par polluant (coherents avec le schema PostgreSQL).
SEUILS = {
    "NO2": (200.0, 400.0),
    "O3": (180.0, 240.0),
    "PM10": (50.0, 80.0),
    "PM25": (None, None),
    "SO2": (300.0, 500.0),
    "CO": (None, None),
}


def construire_silver(spark, chemin_bronze, chemin_silver, date_filtre):
    df = spark.read.json(chemin_bronze)
    total_brut = df.count()
    print(f"Lignes brutes lues : {total_brut}")

    if date_filtre:
        df = df.filter(F.col("date_debut").startswith(date_filtre.replace("-", "/")))

    df = df.withColumn("valeur_num", F.col("valeur").cast(DoubleType()))

    fmt = "yyyy/MM/dd HH:mm:ss"
    df = (df
          .withColumn("horodatage", F.to_timestamp("date_debut", fmt))
          .withColumn("horodatage_fin", F.to_timestamp("date_fin", fmt))
          .withColumn("date_mesure", F.to_date("horodatage")))

    nb_invalides = df.filter(F.col("validite") == "-1").count()
    print(f"Mesures invalides (validite=-1) ecartees : {nb_invalides}")
    df = df.filter(F.col("validite") != "-1")

    avant_dedup = df.count()
    df = df.dropDuplicates(["code_site", "code_polluant", "horodatage"])
    apres_dedup = df.count()
    print(f"Doublons supprimes : {avant_dedup - apres_dedup} "
          f"({avant_dedup} -> {apres_dedup})")

    seuil_info_expr = F.create_map(
        *sum([[F.lit(k), F.lit(v[0])] for k, v in SEUILS.items()], [])
    )
    seuil_alerte_expr = F.create_map(
        *sum([[F.lit(k), F.lit(v[1])] for k, v in SEUILS.items()], [])
    )
    df = (df
          .withColumn("seuil_info", seuil_info_expr[F.col("code_polluant")])
          .withColumn("seuil_alerte", seuil_alerte_expr[F.col("code_polluant")])
          .withColumn(
              "depassement",
              F.when(
                  F.col("seuil_alerte").isNotNull()
                  & (F.col("valeur_num") >= F.col("seuil_alerte")),
                  F.lit("alerte"),
              ).when(
                  F.col("seuil_info").isNotNull()
                  & (F.col("valeur_num") >= F.col("seuil_info")),
                  F.lit("info"),
              ).otherwise(F.lit(None)),
          ))

    silver = df.select(
        "code_site", "nom_site", "organisme", "code_zas", "zas",
        "type_implantation", "type_influence", "code_polluant",
        "horodatage", "horodatage_fin", "date_mesure",
        F.col("valeur_num").alias("valeur"), "unite", "type_valeur",
        "validite", "depassement", "_ingested_at",
    ).withColumn("_processed_at", F.current_timestamp())

    (silver.write.mode("overwrite")
     .partitionBy("date_mesure").parquet(chemin_silver))

    print(f"\nSilver ecrit : {silver.count()} mesures -> {chemin_silver}")
    print("\nRepartition des depassements de seuil :")
    (silver.groupBy("depassement").count().orderBy("depassement").show(truncate=False))


def main():
    parseur = argparse.ArgumentParser(description="Spark Bronze -> Silver")
    parseur.add_argument("--date", help="Filtrer sur une date (YYYY-MM-DD)")
    parseur.add_argument("--local-path", help="Chemin local Bronze (dev hors MinIO)")
    parseur.add_argument("--local-out", help="Chemin local Silver (dev hors MinIO)")
    args = parseur.parse_args()

    if args.local_path:
        spark = spark_utils.creer_spark_local("bronze-to-silver")
        construire_silver(spark, args.local_path, args.local_out, args.date)
    else:
        spark = spark_utils.creer_spark_minio("bronze-to-silver")
        chemin_bronze = spark_utils.s3_path("bronze", "air")
        chemin_silver = spark_utils.s3_path("silver", "air")
        construire_silver(spark, chemin_bronze, chemin_silver, args.date)

    spark.stop()


if __name__ == "__main__":
    main()
PYEOF

# ---------------------------------------------------------------------------
# 3. silver_to_gold.py
# ---------------------------------------------------------------------------
echo ">> Ecriture de processing/spark/silver_to_gold.py..."
cat > processing/spark/silver_to_gold.py << 'PYEOF'
"""Job Spark : transformation Silver -> Gold.

Produit trois datamarts agreges prets pour l'API et le tableau de bord :
  1. moyennes_journalieres : moyenne, min, max par station, polluant et jour
  2. indice_journalier     : indice de qualite de l'air par station et jour
  3. depassements          : liste des depassements de seuil (info / alerte)

L'indice suit la logique de l'indice ATMO : un sous-indice de 1 (bon) a 6
(extremement mauvais) par polluant, l'indice de la station etant le maximum
des sous-indices (le polluant le plus defavorable determine l'indice).

Usage :
    python -m processing.spark.silver_to_gold
    python -m processing.spark.silver_to_gold --local-path silver/air --local-out gold
"""
import argparse

from pyspark.sql import functions as F

from processing.spark import spark_utils

GRILLE_SOUS_INDICE = {
    "NO2":  [(40, 1), (90, 2), (120, 3), (230, 4), (340, 5), (float("inf"), 6)],
    "O3":   [(50, 1), (100, 2), (130, 3), (240, 4), (380, 5), (float("inf"), 6)],
    "PM10": [(20, 1), (40, 2), (50, 3), (100, 4), (150, 5), (float("inf"), 6)],
    "PM25": [(10, 1), (20, 2), (25, 3), (50, 4), (75, 5), (float("inf"), 6)],
    "SO2":  [(100, 1), (200, 2), (350, 3), (500, 4), (750, 5), (float("inf"), 6)],
    "CO":   [(4, 1), (8, 2), (10, 3), (15, 4), (30, 5), (float("inf"), 6)],
}

QUALIFICATIFS = {
    1: "Bon", 2: "Moyen", 3: "Degrade",
    4: "Mauvais", 5: "Tres mauvais", 6: "Extremement mauvais",
}


def _expr_sous_indice():
    """Sous-indice = plus petit indice dont la borne n'est pas depassee.

    Cascade ordonnee du sous-indice le plus eleve vers le plus bas, afin que
    les conditions les plus specifiques (petites valeurs) prennent le dessus.
    """
    expr = F.lit(None)
    for polluant, bornes in GRILLE_SOUS_INDICE.items():
        for borne_sup, indice in sorted(bornes, key=lambda x: x[1], reverse=True):
            cond = (F.col("code_polluant") == polluant) & (F.col("moyenne") <= F.lit(borne_sup))
            expr = F.when(cond, F.lit(indice)).otherwise(expr)
    return expr


def construire_gold(spark, chemin_silver, chemin_gold):
    silver = spark.read.parquet(chemin_silver)
    print(f"Mesures Silver lues : {silver.count()}")

    mesures = silver.withColumn(
        "valeur_agg",
        F.when(F.col("valeur") < 0, F.lit(0.0)).otherwise(F.col("valeur")),
    )

    moyennes = (mesures
                .groupBy("code_site", "nom_site", "code_polluant", "date_mesure", "unite")
                .agg(
                    F.round(F.avg("valeur_agg"), 2).alias("moyenne"),
                    F.round(F.min("valeur_agg"), 2).alias("minimum"),
                    F.round(F.max("valeur_agg"), 2).alias("maximum"),
                    F.count("*").alias("nb_mesures"),
                ))

    (moyennes.write.mode("overwrite")
     .partitionBy("date_mesure").parquet(f"{chemin_gold}/moyennes_journalieres"))
    print(f"Datamart moyennes_journalieres : {moyennes.count()} lignes")

    avec_sous_indice = moyennes.withColumn("sous_indice", _expr_sous_indice())

    indice = (avec_sous_indice
              .groupBy("code_site", "nom_site", "date_mesure")
              .agg(
                  F.max("sous_indice").alias("indice_atmo"),
                  F.expr("max_by(code_polluant, sous_indice)").alias("polluant_resp"),
              ))

    mapping_qualif = F.create_map(
        *sum([[F.lit(k), F.lit(v)] for k, v in QUALIFICATIFS.items()], [])
    )
    indice = indice.withColumn("qualificatif", mapping_qualif[F.col("indice_atmo")])

    (indice.write.mode("overwrite")
     .partitionBy("date_mesure").parquet(f"{chemin_gold}/indice_journalier"))
    print(f"Datamart indice_journalier : {indice.count()} lignes")

    depassements = (silver
                    .filter(F.col("depassement").isNotNull())
                    .select("code_site", "nom_site", "code_polluant",
                            "horodatage", "date_mesure", "valeur", "unite",
                            "depassement"))

    (depassements.write.mode("overwrite")
     .partitionBy("date_mesure").parquet(f"{chemin_gold}/depassements"))
    print(f"Datamart depassements : {depassements.count()} lignes")

    print("\nRepartition des indices de qualite de l'air :")
    (indice.groupBy("indice_atmo", "qualificatif").count()
     .orderBy("indice_atmo").show(truncate=False))
    print("Exemple de moyennes journalieres :")
    (moyennes.orderBy("code_site", "code_polluant")
     .select("code_site", "code_polluant", "moyenne", "minimum", "maximum", "nb_mesures")
     .show(10, truncate=False))


def main():
    parseur = argparse.ArgumentParser(description="Spark Silver -> Gold")
    parseur.add_argument("--local-path", help="Chemin local Silver (dev hors MinIO)")
    parseur.add_argument("--local-out", help="Chemin local Gold (dev hors MinIO)")
    args = parseur.parse_args()

    if args.local_path:
        spark = spark_utils.creer_spark_local("silver-to-gold")
        construire_gold(spark, args.local_path, args.local_out)
    else:
        spark = spark_utils.creer_spark_minio("silver-to-gold")
        chemin_silver = spark_utils.s3_path("silver", "air")
        chemin_gold = spark_utils.s3_path("gold")
        construire_gold(spark, chemin_silver, chemin_gold)

    spark.stop()


if __name__ == "__main__":
    main()
PYEOF

# ---------------------------------------------------------------------------
# 4. Tests d'indice
# ---------------------------------------------------------------------------
echo ">> Ecriture des tests d'indice..."
mkdir -p tests/unit
touch tests/__init__.py tests/unit/__init__.py
cat > tests/unit/test_indice.py << 'PYEOF'
"""Tests de la logique metier de calcul de l'indice de qualite de l'air."""
from processing.spark.silver_to_gold import GRILLE_SOUS_INDICE, QUALIFICATIFS


def sous_indice(polluant: str, moyenne: float) -> int:
    for borne_sup, indice in GRILLE_SOUS_INDICE[polluant]:
        if moyenne <= borne_sup:
            return indice
    raise AssertionError("borne infinie manquante")


def test_o3_degrade():
    assert sous_indice("O3", 101.37) == 3


def test_no2_bon():
    assert sous_indice("NO2", 30.0) == 1


def test_pm25_moyen():
    assert sous_indice("PM25", 18.15) == 2


def test_pm10_borne_exacte():
    assert sous_indice("PM10", 20.0) == 1
    assert sous_indice("PM10", 20.1) == 2


def test_valeur_extreme():
    assert sous_indice("O3", 500.0) == 6
    assert sous_indice("PM10", 1000.0) == 6


def test_grille_complete():
    for polluant, bornes in GRILLE_SOUS_INDICE.items():
        assert len(bornes) == 6, f"{polluant} n'a pas 6 niveaux"
        assert bornes[-1][0] == float("inf"), f"{polluant} sans borne infinie"
        assert [i for _, i in bornes] == [1, 2, 3, 4, 5, 6]


def test_qualificatifs_complets():
    assert set(QUALIFICATIFS.keys()) == {1, 2, 3, 4, 5, 6}
PYEOF

# ---------------------------------------------------------------------------
# 5. Dependances : pyspark
# ---------------------------------------------------------------------------
echo ">> Ajout de pyspark aux dependances..."
mkdir -p processing
cat > processing/requirements.txt << 'EOF'
# Traitement Spark AtmoFrance
pyspark==3.5.1
EOF
grep -q "pyspark" ingestion/requirements.txt 2>/dev/null || true
echo "   Installation de pyspark (peut prendre 1-2 min, ~300 Mo)..."
.venv/bin/pip install --quiet pyspark==3.5.1

# ---------------------------------------------------------------------------
# 6. Tests
# ---------------------------------------------------------------------------
echo ""
echo ">> Execution des tests d'indice..."
.venv/bin/python -m pytest tests/unit/test_indice.py -v

echo ""
echo "=============================================="
echo " Phase 5 installee."
echo "=============================================="
echo " Verifie d'abord ta version de Java (Spark exige Java 8/11/17) :"
echo "   java -version"
echo ""
echo " Puis lance le traitement complet sur le datalake MinIO :"
echo "   source .venv/bin/activate"
echo "   python -m processing.spark.bronze_to_silver"
echo "   python -m processing.spark.silver_to_gold"
echo ""
echo " Note : le premier lancement telecharge les connecteurs S3A"
echo "        (hadoop-aws), cela peut prendre 1-2 minutes."
echo "=============================================="
