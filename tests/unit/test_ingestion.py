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
