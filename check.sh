#!/usr/bin/env bash
#
# AtmoFrance - DIAGNOSTIC COMPLET (version rapport copiable)
# ==========================================================
# Une seule commande qui verifie TOUT et produit un rapport texte
# propre, facile a copier-coller. Sans couleurs (pour un collage lisible).
#
# Usage :
#   bash check.sh
# Ou pour sauvegarder dans un fichier :
#   bash check.sh > rapport_diagnostic.txt
#
set -uo pipefail

PROJET="/home/pourtoi/taf/bahut/atmofrance"
VENV="$PROJET/.venv/bin/python"
cd "$PROJET" 2>/dev/null || { echo "ERREUR : projet introuvable a $PROJET"; exit 1; }

nb_ok=0; nb_ko=0; nb_warn=0
ok()   { echo "[OK]   $1"; nb_ok=$((nb_ok+1)); }
ko()   { echo "[KO]   $1"; nb_ko=$((nb_ko+1)); }
warn() { echo "[WARN] $1"; nb_warn=$((nb_warn+1)); }
section() { echo ""; echo "=== $1 ==="; }

echo "######################################################"
echo "# ATMOFRANCE - RAPPORT DE DIAGNOSTIC"
echo "# Date : $(date '+%Y-%m-%d %H:%M:%S')"
echo "# Machine : $(hostname)"
echo "######################################################"

# ---------- A. PREREQUIS ----------
section "A. PREREQUIS SYSTEME"
command -v docker >/dev/null 2>&1 && ok "Docker : $(docker --version 2>/dev/null)" || ko "Docker absent"
docker compose version >/dev/null 2>&1 && ok "Docker Compose : $(docker compose version --short 2>/dev/null)" || ko "Docker Compose absent"
command -v java >/dev/null 2>&1 && ok "Java : $(java -version 2>&1 | head -1)" || warn "Java non trouve"

# ---------- B. PYTHON ----------
section "B. ENVIRONNEMENTS PYTHON"
if [ -f "$VENV" ]; then
  ok ".venv present : $("$VENV" --version 2>&1)"
  for mod in kafka psycopg pymongo pyspark fastapi uvicorn streamlit folium plotly requests; do
    "$VENV" -c "import $mod" 2>/dev/null && ok "  import $mod" || ko "  import $mod ECHOUE"
  done
  # Versions critiques
  FA=$("$VENV" -c "import fastapi; print(fastapi.__version__)" 2>/dev/null || echo "?")
  ST=$("$VENV" -c "import starlette; print(starlette.__version__)" 2>/dev/null || echo "?")
  echo "       (fastapi=$FA, starlette=$ST)"
else
  ko ".venv absent"
fi
if [ -f "$PROJET/.venv-airflow/bin/python" ]; then
  "$PROJET/.venv-airflow/bin/python" -c "import airflow; print('Airflow', airflow.__version__)" 2>/dev/null \
    && ok ".venv-airflow present (Airflow OK)" || warn ".venv-airflow present, Airflow non importable"
else
  warn ".venv-airflow absent"
fi

# ---------- C. DOCKER ----------
section "C. SERVICES DOCKER"
for svc in atmo-postgres atmo-mongo atmo-minio atmo-kafka atmo-zookeeper; do
  ligne=$(docker compose ps 2>/dev/null | grep "$svc")
  if echo "$ligne" | grep -qiE "healthy|up|running"; then
    ok "$svc actif"
  elif [ -z "$ligne" ]; then
    ko "$svc NON demarre"
  else
    warn "$svc etat incertain"
  fi
done

# ---------- D. BASES ----------
section "D. BASES DE DONNEES (acces + contenu)"
# PostgreSQL
if docker exec atmo-postgres pg_isready -U atmo >/dev/null 2>&1; then
  ok "PostgreSQL accessible"
  for t in station gold_indice_journalier gold_moyennes_journalieres gold_depassements; do
    n=$(docker exec atmo-postgres psql -U atmo -d atmofrance -tAc "SELECT COUNT(*) FROM $t;" 2>/dev/null | tr -d ' ')
    if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then ok "  $t : $n lignes"; else ko "  $t vide ou absente"; fi
  done
else
  ko "PostgreSQL inaccessible"
fi
# MongoDB
NB_DOC=$(docker exec atmo-mongo mongosh -u atmo -p change_me --authenticationDatabase admin atmofrance_raw --quiet --eval "db.stations.countDocuments()" 2>/dev/null | tr -d ' \r\n')
[ -n "$NB_DOC" ] && [ "$NB_DOC" -gt 0 ] 2>/dev/null && ok "MongoDB : $NB_DOC documents" || ko "MongoDB inaccessible ou vide"
# MinIO
if docker exec atmo-minio mc ls local/ >/dev/null 2>&1; then
  ok "MinIO accessible"
  for b in bronze silver gold; do
    n=$(docker exec atmo-minio mc ls --recursive "local/$b/" 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && ok "  bucket $b : $n objets" || warn "  bucket $b vide"
  done
else
  warn "MinIO mc non configure (console: http://localhost:9001)"
fi

# ---------- E. API ----------
section "E. API (si lancee)"
if curl -s http://localhost:8000/health >/dev/null 2>&1; then
  H=$(curl -s http://localhost:8000/health 2>/dev/null)
  ok "API en ligne : $H"
else
  warn "API non joignable sur le port 8000 (lancer : bash lancer_demo.sh)"
fi

# ---------- F. DASHBOARD ----------
section "F. DASHBOARD (si lance)"
if curl -s http://localhost:8501 >/dev/null 2>&1; then
  ok "Dashboard en ligne (port 8501)"
else
  warn "Dashboard non joignable sur 8501 (lancer : bash lancer_demo.sh)"
fi

# ---------- G. TESTS ----------
section "G. TESTS UNITAIRES"
if [ -f "$VENV" ]; then
  R=$("$VENV" -m pytest tests/unit/ -q 2>&1 | tail -1)
  echo "$R" | grep -q "passed" && ok "Tests : $(echo "$R" | grep -oE '[0-9]+ passed')" || ko "Tests : $R"
else
  warn "Tests non lances (.venv absent)"
fi

# ---------- H. FICHIERS ----------
section "H. FICHIERS CLES"
for f in docker-compose.yml Makefile pyproject.toml api/main.py api/queries.py \
         dashboard/app.py infra/airflow/dags/atmofrance_pipeline.py .github/workflows/ci.yml; do
  [ -f "$PROJET/$f" ] && ok "$f" || ko "$f MANQUANT"
done

# ---------- RESUME ----------
echo ""
echo "######################################################"
echo "# RESUME : OK=$nb_ok  WARN=$nb_warn  KO=$nb_ko"
if [ "$nb_ko" -eq 0 ]; then
  echo "# >>> PROJET PRET POUR LA DEMO <<<"
elif [ "$nb_ko" -le 2 ]; then
  echo "# >>> Presque pret - voir les [KO] ci-dessus <<<"
else
  echo "# >>> Corrections necessaires - voir les [KO] <<<"
fi
echo "######################################################"
