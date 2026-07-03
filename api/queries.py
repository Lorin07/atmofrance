"""Acces aux donnees pour l'API : requetes sur PostgreSQL."""
from ingestion import db


def _lignes_en_dicts(cur) -> list:
    colonnes = [desc[0] for desc in cur.description]
    return [dict(zip(colonnes, ligne, strict=False)) for ligne in cur.fetchall()]


def lister_stations() -> list:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    cur.execute("""
        SELECT code_station, nom, type_station, type_influence,
               latitude, longitude
        FROM station
        WHERE geom IS NOT NULL
        ORDER BY nom
    """)
    resultat = _lignes_en_dicts(cur)
    conn.close()
    return resultat


def lister_indices(jour=None) -> list:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    if jour:
        cur.execute("""
            SELECT code_site, nom_site, jour, indice_atmo, qualificatif,
                   polluant_resp, latitude, longitude
            FROM gold_indice_journalier
            WHERE geom IS NOT NULL AND jour = %s
            ORDER BY indice_atmo DESC
        """, (jour,))
    else:
        cur.execute("""
            SELECT code_site, nom_site, jour, indice_atmo, qualificatif,
                   polluant_resp, latitude, longitude
            FROM gold_indice_journalier
            WHERE geom IS NOT NULL
            ORDER BY jour DESC, indice_atmo DESC
        """)
    resultat = _lignes_en_dicts(cur)
    conn.close()
    return resultat


def lister_moyennes(polluant=None, jour=None) -> list:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    conditions = []
    params = []
    if polluant:
        conditions.append("code_polluant = %s")
        params.append(polluant)
    if jour:
        conditions.append("jour = %s")
        params.append(jour)
    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
    cur.execute(f"""
        SELECT code_site, nom_site, code_polluant, jour,
               moyenne, minimum, maximum, nb_mesures, unite
        FROM gold_moyennes_journalieres
        {where}
        ORDER BY jour DESC, moyenne DESC
        LIMIT 2000
    """, params)
    resultat = _lignes_en_dicts(cur)
    conn.close()
    return resultat


def lister_depassements(jour=None) -> list:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    if jour:
        cur.execute("""
            SELECT code_site, nom_site, code_polluant, horodatage, jour,
                   valeur, unite, depassement
            FROM gold_depassements
            WHERE jour = %s
            ORDER BY horodatage DESC
        """, (jour,))
    else:
        cur.execute("""
            SELECT code_site, nom_site, code_polluant, horodatage, jour,
                   valeur, unite, depassement
            FROM gold_depassements
            ORDER BY horodatage DESC
            LIMIT 1000
        """)
    resultat = _lignes_en_dicts(cur)
    conn.close()
    return resultat


def statistiques_globales() -> dict:
    conn = db.connexion_postgres()
    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) FROM station")
    nb_stations = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM station WHERE geom IS NOT NULL")
    nb_stations_geo = cur.fetchone()[0]
    cur.execute("SELECT COUNT(DISTINCT jour) FROM gold_indice_journalier")
    nb_jours = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM gold_depassements WHERE depassement = 'alerte'")
    nb_alertes = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM gold_depassements WHERE depassement = 'info'")
    nb_info = cur.fetchone()[0]
    cur.execute("""
        SELECT qualificatif, COUNT(*) AS n
        FROM gold_indice_journalier
        GROUP BY qualificatif
        ORDER BY MIN(indice_atmo)
    """)
    repartition = _lignes_en_dicts(cur)

    conn.close()
    return {
        "nb_stations": nb_stations,
        "nb_stations_geolocalisees": nb_stations_geo,
        "nb_jours_donnees": nb_jours,
        "nb_depassements_alerte": nb_alertes,
        "nb_depassements_info": nb_info,
        "repartition_indices": repartition,
    }
