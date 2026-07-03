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
