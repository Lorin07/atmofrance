"""Producteur de flux : lit un fichier de mesures Geod'Air (flux E2) et publie
chaque mesure dans le topic Kafka `air-raw`.

Le fichier source est un CSV point-virgule, encode UTF-8 avec BOM, dont le
format a ete etabli par inspection des donnees reelles :

    "Date de debut";"Date de fin";"Organisme";"code zas";"Zas";"code site";
    "nom site";"type d'implantation";"Polluant";"type d'influence";...;
    "valeur";"valeur brute";"unite de mesure";...;"code qualite";"validite"

Seuls les 6 polluants reglementaires sont conserves. Les mesures sont envoyees
telles quelles (donnees brutes) : le nettoyage est fait plus loin, en Silver.

Usage :
    python -m ingestion.producers.geodair_producer --date 2026-07-01
    python -m ingestion.producers.geodair_producer --file chemin/vers/fichier.csv
    python -m ingestion.producers.geodair_producer --date 2026-07-01 --rate 200
"""
import argparse
import csv
import io
import json
import sys
import time
import urllib.request
from datetime import datetime, timezone

from kafka import KafkaProducer

from ingestion import config


def _telecharger_csv(date_str: str) -> str:
    """Recupere le fichier journalier Geod'Air pour une date donnee (YYYY-MM-DD)."""
    annee = date_str[:4]
    url = f"{config.GEODAIR_FILES_BASE}/{annee}/FR_E2_{date_str}.csv"
    print(f"Telechargement : {url}")
    with urllib.request.urlopen(url, timeout=60) as reponse:
        contenu = reponse.read()
    # Decodage UTF-8 en retirant le BOM eventuel
    return contenu.decode("utf-8-sig")


def _lire_csv_local(chemin: str) -> str:
    with open(chemin, encoding="utf-8-sig") as f:
        return f.read()


def _iterer_mesures(texte_csv: str):
    """Genere les mesures retenues a partir du contenu CSV.

    Chaque mesure est un dictionnaire pret a etre serialise en JSON.
    Les lignes dont le polluant n'est pas dans le perimetre sont ignorees.
    """
    lecteur = csv.DictReader(io.StringIO(texte_csv), delimiter=";")
    for ligne in lecteur:
        polluant_source = (ligne.get("Polluant") or "").strip()
        if polluant_source not in config.POLLUANTS_RETENUS:
            continue

        unite_source = (ligne.get("unité de mesure") or "").strip()
        yield {
            "date_debut": (ligne.get("Date de début") or "").strip(),
            "date_fin": (ligne.get("Date de fin") or "").strip(),
            "organisme": (ligne.get("Organisme") or "").strip(),
            "code_zas": (ligne.get("code zas") or "").strip(),
            "zas": (ligne.get("Zas") or "").strip(),
            "code_site": (ligne.get("code site") or "").strip(),
            "nom_site": (ligne.get("nom site") or "").strip(),
            "type_implantation": (ligne.get("type d'implantation") or "").strip(),
            "polluant_source": polluant_source,
            "code_polluant": config.POLLUANTS_RETENUS[polluant_source],
            "type_influence": (ligne.get("type d'influence") or "").strip(),
            "type_valeur": (ligne.get("type de valeur") or "").strip(),
            "valeur": (ligne.get("valeur") or "").strip(),
            "valeur_brute": (ligne.get("valeur brute") or "").strip(),
            "unite_source": unite_source,
            "unite": config.UNITES_NORM.get(unite_source, unite_source),
            "code_qualite": (ligne.get("code qualité") or "").strip(),
            "validite": (ligne.get("validité") or "").strip(),
            # Metadonnees de lineage (tracabilite)
            "_ingested_at": datetime.now(timezone.utc).isoformat(),
        }


def _creer_producer() -> KafkaProducer:
    return KafkaProducer(
        bootstrap_servers=config.KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
        key_serializer=lambda k: k.encode("utf-8") if k else None,
        acks="all",           # garantie d'ecriture cote broker
        retries=3,
        linger_ms=50,         # petit buffer pour ameliorer le debit
    )


def produire(date_str, chemin, rate: int) -> None:
    """Publie les mesures dans Kafka.

    rate : nombre maximum de messages par seconde (0 = aucune limite).
    """
    if chemin:
        print(f"Lecture du fichier local : {chemin}")
        texte = _lire_csv_local(chemin)
    elif date_str:
        texte = _telecharger_csv(date_str)
    else:
        print("Erreur : preciser --date ou --file", file=sys.stderr)
        sys.exit(1)

    producer = _creer_producer()
    topic = config.KAFKA_TOPIC_AIR

    envoyes = 0
    debut = time.monotonic()
    intervalle = 1.0 / rate if rate > 0 else 0.0

    for mesure in _iterer_mesures(texte):
        # La cle Kafka = code site + polluant, pour regrouper une meme serie
        cle = f"{mesure['code_site']}|{mesure['code_polluant']}"
        producer.send(topic, key=cle, value=mesure)
        envoyes += 1

        if envoyes % 5000 == 0:
            print(f"  {envoyes} mesures envoyees...")

        if intervalle:
            time.sleep(intervalle)

    producer.flush()
    producer.close()

    duree = time.monotonic() - debut
    print(
        f"\nTermine. {envoyes} mesures publiees dans le topic '{topic}' "
        f"en {duree:.1f}s."
    )


def main() -> None:
    parseur = argparse.ArgumentParser(description="Producteur Geod'Air vers Kafka")
    groupe = parseur.add_mutually_exclusive_group(required=True)
    groupe.add_argument("--date", help="Date du fichier a ingerer (YYYY-MM-DD)")
    groupe.add_argument("--file", help="Chemin d'un fichier CSV local")
    parseur.add_argument(
        "--rate",
        type=int,
        default=0,
        help="Debit max en messages/seconde (0 = illimite). "
        "Utiliser une valeur (ex. 200) pour simuler un flux temps reel visible.",
    )
    args = parseur.parse_args()
    produire(args.date, args.file, args.rate)


if __name__ == "__main__":
    main()
