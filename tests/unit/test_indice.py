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
