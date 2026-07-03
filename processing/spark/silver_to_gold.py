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
