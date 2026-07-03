"""Tests de l'extraction de commune depuis les noms de station (sans reseau)."""
from ingestion.geocoding import extraire_commune


def test_commune_simple():
    assert extraire_commune("CARPENTRAS", "ZAG AVIGNON") == "CARPENTRAS"
    assert extraire_commune("ANGLET", "ZAG BAYONNE") == "ANGLET"


def test_commune_avec_lieu_dit():
    assert extraire_commune("Roubaix Serres", "ZAG LILLE") == "Roubaix"
    assert extraire_commune("Grenoble Les Frenes", "ZAG GRENOBLE") == "Grenoble"


def test_separateurs():
    assert extraire_commune("Merignac - Magudas", "ZAG BORDEAUX") == "Merignac"
    assert extraire_commune("Bordeaux_GAUTIER", "ZAG BORDEAUX") == "Bordeaux"


def test_code_routier_repli_zas():
    assert extraire_commune("A7 SUD LYONNAIS", "ZAG LYON") == "Lyon"
    assert extraire_commune("N118 Sud", "ZAG PARIS") == "Paris"


def test_zone_industrielle_repli_zas():
    assert extraire_commune("ZI Estuaire Adour", "ZAG BAYONNE") == "Bayonne"


def test_commune_composee():
    assert extraire_commune("St Martin d'Heres", "ZAG GRENOBLE") == "St Martin d'Heres"
    assert extraire_commune("St Denis Stade", "ZAG PARIS") == "St Denis"


def test_nom_vide_repli_zas():
    assert extraire_commune("", "ZAG METZ") == "Metz"
