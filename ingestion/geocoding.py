"""Geocodage des stations de mesure via l'API adresse.data.gouv.fr.

Le fichier de mesures Geod'Air ne contient pas les coordonnees des stations.
On les reconstruit en extrayant la commune du nom de station puis en la
geocodant via l'API officielle (Base Adresse Nationale), gratuite et sans cle.
"""
import json
import re as _re
import time
import urllib.parse
import urllib.request

API_ADRESSE = "https://api-adresse.data.gouv.fr/search/"

PARASITES = {
    "periurbaine", "periurb", "urbain", "urbaine", "rurale", "trafic",
    "stade", "mairie", "zi", "za", "rocade", "sud", "nord", "est", "ouest",
    "boulevards", "centre", "peripherique", "autoroute", "zone", "parc",
}

_MOTIF_NON_COMMUNE = _re.compile(r"^(a\d+|n\d+|d\d+|rd\d+|zi|za)$", _re.IGNORECASE)

PREFIXES_COMPOSES = {"st", "saint", "sainte", "ste", "le", "la", "les", "aix"}


def _nettoyer_zas(zas: str) -> str:
    nom = zas
    for prefixe in ("ZAG", "ZAR", "ZA "):
        nom = nom.replace(prefixe, "")
    return nom.strip().title()


def extraire_commune(nom_site: str, zas: str) -> str:
    """Extrait une commune candidate depuis le nom de station."""
    nom = nom_site.replace("_", " ").replace("-", " ")
    mots = [m for m in nom.split() if m]
    if not mots:
        return _nettoyer_zas(zas)

    premier = mots[0]
    if _MOTIF_NON_COMMUNE.match(premier) or premier.lower() in PARASITES:
        return _nettoyer_zas(zas)

    if premier.lower() in PREFIXES_COMPOSES and len(mots) > 1:
        composee = [premier]
        for mot in mots[1:]:
            if mot.lower() in PARASITES:
                break
            composee.append(mot)
        return " ".join(composee)

    return premier


def geocoder_commune(commune: str):
    """Retourne (longitude, latitude, label, contexte) ou None."""
    params = urllib.parse.urlencode({"q": commune, "type": "municipality", "limit": 1})
    url = f"{API_ADRESSE}?{params}"
    try:
        with urllib.request.urlopen(url, timeout=15) as reponse:
            data = json.loads(reponse.read().decode("utf-8"))
    except Exception:
        return None
    features = data.get("features", [])
    if not features:
        return None
    coords = features[0]["geometry"]["coordinates"]
    label = features[0]["properties"].get("label", commune)
    contexte = features[0]["properties"].get("context", "")
    return (coords[0], coords[1], label, contexte)


class GeocodeurStations:
    """Geocode un ensemble de stations avec cache par commune."""

    def __init__(self, delai: float = 0.05):
        self._cache = {}
        self._delai = delai

    def geocoder(self, nom_site: str, zas: str) -> dict:
        commune = extraire_commune(nom_site, zas)
        cle = commune.lower()
        if cle not in self._cache:
            resultat = geocoder_commune(commune)
            self._cache[cle] = resultat
            if self._delai:
                time.sleep(self._delai)
        resultat = self._cache[cle]
        if resultat:
            lon, lat, label, contexte = resultat
            return {
                "commune_extraite": commune, "commune_label": label,
                "contexte": contexte, "longitude": lon, "latitude": lat,
                "geocode_ok": True,
            }
        return {
            "commune_extraite": commune, "commune_label": None,
            "contexte": None, "longitude": None, "latitude": None,
            "geocode_ok": False,
        }

    @property
    def nb_communes_geocodees(self) -> int:
        return sum(1 for v in self._cache.values() if v)

    @property
    def nb_communes_total(self) -> int:
        return len(self._cache)
