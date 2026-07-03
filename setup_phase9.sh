#!/usr/bin/env bash
#
# AtmoFrance - Phase 9 : dashboard Streamlit + carte interactive
# A lancer depuis le dossier atmofrance/ apres les phases precedentes.
#
set -euo pipefail

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis le dossier atmofrance/"
  exit 1
fi
if [ ! -d .venv ]; then
  echo "ERREUR : environnement .venv absent"
  exit 1
fi

echo ">> Phase 9 : dashboard Streamlit"

mkdir -p dashboard

# ---------------------------------------------------------------------------
# 1. Application Streamlit
# ---------------------------------------------------------------------------
echo ">> Ecriture de dashboard/app.py..."
cat > dashboard/app.py << 'PYEOF'
"""Tableau de bord AtmoFrance (Streamlit).

Lancement :
    streamlit run dashboard/app.py
"""
import folium
import pandas as pd
import plotly.express as px
import requests
import streamlit as st
from folium.plugins import MarkerCluster
from streamlit_folium import st_folium

API_URL = "http://localhost:8000"

COULEURS_INDICE = {
    1: "#4CAF50", 2: "#CDDC39", 3: "#FFC107",
    4: "#FF5722", 5: "#9C27B0", 6: "#7B1FA2",
}

st.set_page_config(page_title="AtmoFrance", layout="wide")


@st.cache_data(ttl=300)
def charger(endpoint: str) -> dict:
    reponse = requests.get(f"{API_URL}{endpoint}", timeout=30)
    reponse.raise_for_status()
    return reponse.json()


def entete():
    st.title("AtmoFrance - Qualite de l'air en France")
    st.caption("Surveillance des concentrations de polluants atmospheriques "
               "et de leur impact sanitaire.")


def afficher_kpi(stats: dict):
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Stations surveillees", stats["nb_stations"])
    col2.metric("Stations cartographiees", stats["nb_stations_geolocalisees"])
    col3.metric("Depassements (alerte)", stats["nb_depassements_alerte"])
    col4.metric("Depassements (info)", stats["nb_depassements_info"])


def afficher_carte(indices: list, filtre_qualif):
    st.subheader("Carte des indices de qualite de l'air")
    df = pd.DataFrame(indices)
    if df.empty:
        st.warning("Aucune donnee d'indice disponible.")
        return
    if filtre_qualif and filtre_qualif != "Tous":
        df = df[df["qualificatif"] == filtre_qualif]
    if df.empty:
        st.info("Aucune station ne correspond au filtre.")
        return

    carte = folium.Map(location=[46.6, 2.4], zoom_start=6, tiles="cartodbpositron")
    cluster = MarkerCluster().add_to(carte)
    for _, ligne in df.iterrows():
        indice = int(ligne["indice_atmo"])
        couleur = COULEURS_INDICE.get(indice, "#999999")
        popup = folium.Popup(
            f"<b>{ligne['nom_site']}</b><br>"
            f"Indice : {indice} ({ligne['qualificatif']})<br>"
            f"Polluant responsable : {ligne['polluant_resp']}",
            max_width=250,
        )
        folium.CircleMarker(
            location=[ligne["latitude"], ligne["longitude"]],
            radius=6, color=couleur, fill=True, fill_color=couleur,
            fill_opacity=0.8, popup=popup, tooltip=ligne["nom_site"],
        ).add_to(cluster)
    st_folium(carte, use_container_width=True, height=500)


def afficher_repartition(stats: dict):
    st.subheader("Repartition des indices")
    rep = pd.DataFrame(stats["repartition_indices"])
    if rep.empty:
        st.info("Pas de donnees.")
        return
    fig = px.bar(
        rep, x="qualificatif", y="n",
        labels={"qualificatif": "Qualite de l'air", "n": "Nombre de stations"},
        color="qualificatif",
        color_discrete_map={
            "Bon": "#4CAF50", "Moyen": "#CDDC39", "Degrade": "#FFC107",
            "Mauvais": "#FF5722", "Tres mauvais": "#9C27B0",
            "Extremement mauvais": "#7B1FA2",
        },
    )
    fig.update_layout(showlegend=False)
    st.plotly_chart(fig, use_container_width=True)


def afficher_moyennes_polluant(polluant: str):
    st.subheader(f"Stations les plus exposees - {polluant}")
    data = charger(f"/moyennes?polluant={polluant}")
    df = pd.DataFrame(data["moyennes"])
    if df.empty:
        st.info("Pas de donnees pour ce polluant.")
        return
    top = df.nlargest(15, "moyenne")[["nom_site", "moyenne", "maximum", "unite"]]
    fig = px.bar(
        top.sort_values("moyenne"), x="moyenne", y="nom_site",
        orientation="h", labels={"moyenne": "Moyenne journaliere", "nom_site": ""},
    )
    st.plotly_chart(fig, use_container_width=True)


def afficher_depassements():
    st.subheader("Depassements de seuils reglementaires")
    data = charger("/depassements")
    df = pd.DataFrame(data["depassements"])
    if df.empty:
        st.info("Aucun depassement enregistre.")
        return
    affichage = df[["nom_site", "code_polluant", "horodatage",
                    "valeur", "unite", "depassement"]].copy()
    affichage.columns = ["Station", "Polluant", "Horodatage",
                         "Valeur", "Unite", "Niveau"]
    st.dataframe(affichage, use_container_width=True, height=300)


def main():
    entete()
    try:
        stats = charger("/stats")
    except Exception as exc:
        st.error(f"Impossible de contacter l'API ({API_URL}). "
                 f"Verifiez qu'elle est demarree. Detail : {exc}")
        st.stop()

    afficher_kpi(stats)
    st.divider()

    st.sidebar.header("Filtres")
    qualificatifs = ["Tous"] + [r["qualificatif"] for r in stats["repartition_indices"]]
    filtre_qualif = st.sidebar.selectbox("Qualite de l'air", qualificatifs)
    polluant = st.sidebar.selectbox(
        "Polluant (graphique)", ["NO2", "O3", "PM10", "PM25", "SO2", "CO"]
    )

    indices = charger("/indices")["indices"]
    afficher_carte(indices, filtre_qualif)
    st.divider()

    col_gauche, col_droite = st.columns(2)
    with col_gauche:
        afficher_repartition(stats)
    with col_droite:
        afficher_moyennes_polluant(polluant)

    st.divider()
    afficher_depassements()

    st.caption("Donnees : Geod'Air / LCSQA (Licence Ouverte). "
               "Geolocalisation : Base Adresse Nationale.")


if __name__ == "__main__":
    main()
PYEOF

# ---------------------------------------------------------------------------
# 2. Dependances dashboard
# ---------------------------------------------------------------------------
echo ">> Ecriture de dashboard/requirements.txt et installation..."
cat > dashboard/requirements.txt << 'EOF'
# Dashboard AtmoFrance
streamlit==1.36.0
folium==0.16.0
streamlit-folium==0.21.1
plotly==5.22.0
pandas==2.2.2
requests==2.32.3
EOF
echo "   Installation (streamlit, folium, plotly... peut prendre 1-2 min)"
.venv/bin/pip install --quiet \
  streamlit==1.36.0 folium==0.16.0 streamlit-folium==0.21.1 \
  plotly==5.22.0 pandas==2.2.2 requests==2.32.3

echo ""
echo "=============================================="
echo " Phase 9 terminee."
echo "=============================================="
echo " IMPORTANT : l'API doit tourner dans un AUTRE terminal :"
echo "   source .venv/bin/activate"
echo "   uvicorn api.main:app --host 0.0.0.0 --port 8000"
echo ""
echo " Puis lance le dashboard dans CE terminal :"
echo "   source .venv/bin/activate"
echo "   streamlit run dashboard/app.py"
echo ""
echo " Le dashboard s'ouvrira dans ton navigateur :"
echo "   http://localhost:8501"
echo "=============================================="
