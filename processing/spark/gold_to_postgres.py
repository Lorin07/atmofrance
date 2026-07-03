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
