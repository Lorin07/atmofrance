"""Construction et chargement du referentiel des stations de mesure.

  1. lecture des stations distinctes depuis la zone Silver (Spark / MinIO)
  2. geocodage de chaque commune via l'API adresse.data.gouv.fr (avec cache)
  3. ecriture dans PostgreSQL/PostGIS (table station, geometrie)
  4. ecriture des documents bruts dans MongoDB (collection stations)

Usage :
    python -m ingestion.load_stations
"""
from processing.spark import spark_utils

from ingestion import db
from ingestion.geocoding import GeocodeurStations


def lire_stations_silver() -> list:
    spark = spark_utils.creer_spark_minio("load-stations")
    silver = spark.read.parquet(spark_utils.s3_path("silver", "air"))
    stations = (silver
                .select("code_site", "nom_site", "organisme",
                        "code_zas", "zas", "type_implantation", "type_influence")
                .dropDuplicates(["code_site"])
                .orderBy("code_site")
                .collect())
    spark.stop()
    return [row.asDict() for row in stations]


def enrichir_geocodage(stations: list) -> list:
    geocodeur = GeocodeurStations()
    enrichies = []
    for i, st in enumerate(stations, 1):
        geo = geocodeur.geocoder(st["nom_site"], st["zas"] or "")
        st.update(geo)
        enrichies.append(st)
        if i % 50 == 0:
            print(f"  {i}/{len(stations)} stations geocodees "
                  f"({geocodeur.nb_communes_geocodees} communes distinctes)")
    print(f"\nGeocodage termine : "
          f"{geocodeur.nb_communes_geocodees}/{geocodeur.nb_communes_total} "
          f"communes distinctes localisees.")
    nb_ok = sum(1 for s in enrichies if s["geocode_ok"])
    print(f"Stations localisees : {nb_ok}/{len(enrichies)} "
          f"({100 * nb_ok // len(enrichies)}%).")
    return enrichies


def charger_postgres(stations: list) -> None:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    inseres = 0
    for st in stations:
        lon = st.get("longitude")
        lat = st.get("latitude")
        geom_sql = ("ST_SetSRID(ST_MakePoint(%s, %s), 4326)"
                    if lon is not None and lat is not None else "NULL")
        params = [st["code_site"], st["nom_site"], st.get("type_implantation"),
                  st.get("type_influence"), lat, lon]
        params_geom = [lon, lat] if lon is not None and lat is not None else []
        cur.execute(
            f"""
            INSERT INTO station
                (code_station, nom, type_station, type_influence,
                 latitude, longitude, geom)
            VALUES (%s, %s, %s, %s, %s, %s, {geom_sql})
            ON CONFLICT (code_station) DO UPDATE SET
                nom = EXCLUDED.nom,
                type_station = EXCLUDED.type_station,
                type_influence = EXCLUDED.type_influence,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                geom = EXCLUDED.geom
            """,
            params + params_geom,
        )
        inseres += 1
    conn.commit()
    cur.close()
    conn.close()
    print(f"PostgreSQL : {inseres} stations chargees dans la table 'station'.")


def charger_mongo(stations: list) -> None:
    client, base = db.base_mongo()
    collection = base["stations"]
    collection.delete_many({})
    documents = []
    for st in stations:
        doc = dict(st)
        doc["_id"] = st["code_site"]
        documents.append(doc)
    if documents:
        collection.insert_many(documents)
    print(f"MongoDB : {len(documents)} documents stations dans la collection 'stations'.")
    client.close()


def main() -> None:
    print("1. Lecture des stations depuis Silver...")
    stations = lire_stations_silver()
    print(f"   {len(stations)} stations distinctes trouvees.\n")
    print("2. Geocodage des communes...")
    stations = enrichir_geocodage(stations)
    print("\n3. Chargement dans PostgreSQL/PostGIS...")
    charger_postgres(stations)
    print("\n4. Chargement dans MongoDB...")
    charger_mongo(stations)
    print("\nReferentiel stations construit avec succes.")


if __name__ == "__main__":
    main()
