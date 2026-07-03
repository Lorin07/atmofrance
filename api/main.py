"""API REST AtmoFrance.

Lancement :
    uvicorn api.main:app --host 0.0.0.0 --port 8000 --reload
"""
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from api import queries

app = FastAPI(
    title="AtmoFrance API",
    description="API de consultation de la qualite de l'air en France "
                "(mesures Geod'Air, indices ATMO, depassements de seuils).",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", tags=["Accueil"])
def accueil():
    return {
        "service": "AtmoFrance API",
        "version": "1.0.0",
        "ressources": {
            "/health": "Etat de sante de l'API",
            "/stations": "Liste des stations de mesure geolocalisees",
            "/indices": "Indices de qualite de l'air par station",
            "/moyennes": "Moyennes journalieres par polluant",
            "/depassements": "Depassements de seuils reglementaires",
            "/stats": "Statistiques globales",
            "/docs": "Documentation interactive (Swagger)",
        },
    }


@app.get("/health", tags=["Systeme"])
def health():
    try:
        stats = queries.statistiques_globales()
        return {"status": "ok", "base": "accessible",
                "stations": stats["nb_stations"]}
    except Exception as exc:
        return {"status": "degraded", "base": "inaccessible",
                "detail": str(exc)[:200]}


@app.get("/stations", tags=["Donnees"])
def stations():
    resultat = queries.lister_stations()
    return {"count": len(resultat), "stations": resultat}


@app.get("/indices", tags=["Donnees"])
def indices(jour: str | None = Query(None, description="Filtre AAAA-MM-JJ")):
    resultat = queries.lister_indices(jour)
    return {"count": len(resultat), "jour": jour, "indices": resultat}


@app.get("/moyennes", tags=["Donnees"])
def moyennes(
    polluant: str | None = Query(None, description="NO2, O3, PM10, PM25, SO2, CO"),
    jour: str | None = Query(None, description="Filtre AAAA-MM-JJ"),
):
    resultat = queries.lister_moyennes(polluant, jour)
    return {"count": len(resultat), "polluant": polluant, "jour": jour,
            "moyennes": resultat}


@app.get("/depassements", tags=["Donnees"])
def depassements(jour: str | None = Query(None, description="Filtre AAAA-MM-JJ")):
    resultat = queries.lister_depassements(jour)
    return {"count": len(resultat), "jour": jour, "depassements": resultat}


@app.get("/stats", tags=["Donnees"])
def stats():
    return queries.statistiques_globales()
