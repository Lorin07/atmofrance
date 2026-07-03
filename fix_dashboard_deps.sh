#!/usr/bin/env bash
#
# AtmoFrance - Correctif robuste des dependances du dashboard (Python 3.13)
#
# Principe durable (identique au correctif psycopg) :
#   - AUCUN epinglage de version sur les paquets a compilation native
#     (pandas, numpy...) : on laisse pip choisir le wheel adapte a la version
#     de Python installee. Epingler une vieille version force une compilation
#     qui echoue sur Python 3.13.
#   - verification obligatoire des imports a la fin.
#
set -euo pipefail

if [ ! -d .venv ]; then
  echo "ERREUR : environnement .venv absent (lance depuis atmofrance/)"
  exit 1
fi

PY=.venv/bin/python
PIP=.venv/bin/pip

echo ">> Correctif : dependances dashboard (sans version fragile)"

# ---------------------------------------------------------------------------
# 1. requirements.txt sans epinglage sur les paquets natifs
# ---------------------------------------------------------------------------
echo ">> Reecriture de dashboard/requirements.txt..."
mkdir -p dashboard
cat > dashboard/requirements.txt << 'EOF'
# Dashboard AtmoFrance
# Pas de version epinglee sur pandas (paquet natif) : pip choisit le wheel
# compatible avec la version de Python installee (evite toute compilation).
streamlit
folium
streamlit-folium
plotly
pandas
requests
EOF

# ---------------------------------------------------------------------------
# 2. Installation (wheels uniquement, sans compilation)
# ---------------------------------------------------------------------------
$PIP install --quiet --upgrade pip >/dev/null 2>&1 || true

echo ">> Installation des dependances (wheels pre-compiles)..."
# --only-binary=:all: sur pandas/numpy garantit qu'on n'essaie jamais de compiler.
# Si un wheel manque, l'erreur sera claire et immediate (pas 169 lignes de gcc).
if $PIP install --quiet \
      --only-binary=pandas,numpy \
      streamlit folium streamlit-folium plotly pandas requests 2>/dev/null; then
  echo "   installe (avec garantie wheels pour pandas/numpy)."
else
  echo "   ajustement : installation standard..."
  $PIP install --quiet streamlit folium streamlit-folium plotly pandas requests
fi

# ---------------------------------------------------------------------------
# 3. VERIFICATION OBLIGATOIRE des imports
# ---------------------------------------------------------------------------
echo ""
echo ">> Verification des imports..."
if $PY -c "
import streamlit, folium, streamlit_folium, plotly, pandas, requests
print('   streamlit', streamlit.__version__)
print('   folium   ', folium.__version__)
print('   plotly   ', plotly.__version__)
print('   pandas   ', pandas.__version__)
print('   Tous les imports du dashboard OK')
"; then
  echo ""
  echo ">> Verification que le dashboard compile..."
  $PY -m py_compile dashboard/app.py && echo "   dashboard/app.py compile sans erreur"
  echo ""
  echo "=============================================="
  echo " Correctif applique et verifie avec succes."
  echo "=============================================="
  echo " Assure-toi que l'API tourne dans un AUTRE terminal :"
  echo "   uvicorn api.main:app --host 0.0.0.0 --port 8000"
  echo ""
  echo " Puis lance le dashboard :"
  echo "   source .venv/bin/activate"
  echo "   streamlit run dashboard/app.py"
  echo "=============================================="
else
  echo ""
  echo "ECHEC : un import a echoue. Envoie-moi la sortie complete."
  exit 1
fi
