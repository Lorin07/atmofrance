#!/usr/bin/env bash
#
# AtmoFrance - DIAGNOSTIC COMPLET
# ================================
# Verifie point par point que tout est en place et fonctionnel.
# Affiche un rapport clair OK / KO. A lancer a tout moment.
#
set -uo pipefail

PROJET="/home/pourtoi/taf/bahut/atmofrance"
VENV="$PROJET/.venv/bin/python"
cd "$PROJET" 2>/dev/null || { echo "ERREUR : projet introuvable"; exit 1; }

# Couleurs
VERT='\033[0;32m'; ROUGE='\033[0;31m'; JAUNE='\033[0;33m'; RESET='\033[0m'
OK="${VERT}[ OK ]${RESET}"; KO="${ROUGE}[ KO ]${RESET}"; WARN="${JAUNE}[WARN]${RESET}"

nb_ok=0; nb_ko=0; nb_warn=0
ok()   { echo -e "$OK $1";   nb_ok=$((nb_ok+1)); }
ko()   { echo -e "$KO $1";   nb_ko=$((nb_ko+1)); }
warn() { echo -e "$WARN $1"; nb_warn=$((nb_warn+1)); }

echo "=============================================="
echo " AtmoFrance - Diagnostic complet"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="
echo ""

# ============ A. PREREQUIS SYSTEME ============
echo "--- A. Prerequis systeme ---"
command -v docker >/dev/null 2>&1 && ok "Docker installe ($(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1))" || ko "Docker absent"
docker compose version >/dev/null 2>&1 && ok "Docker Compose disponible" || ko "Docker Compose absent"
command -v java >/dev/null 2>&1 && ok "Java installe ($(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1))" || warn "Java non trouve dans le PATH (necessaire pour Spark)"
echo ""

# ============ B. ENVIRONNEMENTS PYTHON ============
echo "--- B. Environnements Python ---"
if [ -d "$PROJET/.venv" ]; then
  PYVER=$("$VENV" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  ok "Environnement .venv present (Python $PYVER)"
  # Dependances cles
  for mod in kafka psycopg pymongo pyspark fastapi streamlit; do
    if "$VENV" -c "import $mod" 2>/dev/null; then
      ok "  module $mod importable"
    else
      ko "  module $mod MANQUANT dans .venv"
    fi
  done
else
  ko "Environnement .venv absent (lancer reprendre_projet.sh)"
fi
if [ -d "$PROJET/.venv-airflow" ]; then
  "$PROJET/.venv-airflow/bin/python" -c "import airflow" 2>/dev/null \
    && ok "Environnement .venv-airflow present (Airflow OK)" \
    || warn ".venv-airflow present mais Airflow non importable"
else
  warn "Environnement .venv-airflow absent (Airflow non installe)"
fi
echo ""

# ============ C. SERVICES DOCKER ============
echo "--- C. Services Docker ---"
for svc in atmo-postgres atmo-mongo atmo-minio atmo-kafka atmo-zookeeper; do
  etat=$(docker compose ps 2>/dev/null | grep "$svc" | grep -oE "healthy|running|Up|Exited|Restarting" | head -1)
  if echo "$etat" | grep -qE "healthy|running|Up"; then
    ok "$svc ($etat)"
  elif [ -z "$etat" ]; then
    ko "$svc non demarre"
  else
    warn "$svc etat: $etat"
  fi
done
echo ""

# ============ D. BASES DE DONNEES ============
echo "--- D. Bases de donnees (acces + contenu) ---"

# PostgreSQL
if docker exec atmo-postgres pg_isready -U atmo >/dev/null 2>&1; then
  ok "PostgreSQL accessible"
  NB_ST=$(docker exec atmo-postgres psql -U atmo -d atmofrance -tAc "SELECT COUNT(*) FROM station;" 2>/dev/null | tr -d ' ')
  NB_IND=$(docker exec atmo-postgres psql -U atmo -d atmofrance -tAc "SELECT COUNT(*) FROM gold_indice_journalier;" 2>/dev/null | tr -d ' ')
  [ -n "$NB_ST" ] && [ "$NB_ST" -gt 0 ] 2>/dev/null && ok "  table station : $NB_ST lignes" || ko "  table station vide"
  [ -n "$NB_IND" ] && [ "$NB_IND" -gt 0 ] 2>/dev/null && ok "  table gold_indice_journalier : $NB_IND lignes" || ko "  table gold_indice_journalier vide"
else
  ko "PostgreSQL inaccessible"
fi

# MongoDB
NB_DOC=$(docker exec atmo-mongo mongosh -u atmo -p change_me --authenticationDatabase admin atmofrance_raw --quiet --eval "db.stations.countDocuments()" 2>/dev/null | tr -d ' \r\n')
if [ -n "$NB_DOC" ] && [ "$NB_DOC" -gt 0 ] 2>/dev/null; then
  ok "MongoDB accessible ($NB_DOC documents stations)"
else
  ko "MongoDB inaccessible ou vide"
fi

# MinIO buckets
if docker exec atmo-minio mc ls local/ >/dev/null 2>&1; then
  ok "MinIO accessible"
  for bucket in bronze silver gold; do
    if docker exec atmo-minio mc ls "local/$bucket/" >/dev/null 2>&1; then
      nb_obj=$(docker exec atmo-minio mc ls --recursive "local/$bucket/" 2>/dev/null | wc -l)
      ok "  bucket $bucket : $nb_obj objet(s)"
    else
      warn "  bucket $bucket vide ou absent"
    fi
  done
else
  warn "MinIO : client mc non configure (alias local). Console web : http://localhost:9001"
fi
echo ""

# ============ E. TESTS ============
echo "--- E. Tests unitaires ---"
if [ -d "$PROJET/.venv" ]; then
  RESULT=$("$VENV" -m pytest tests/unit/ -q 2>&1 | tail -1)
  if echo "$RESULT" | grep -q "passed"; then
    NB=$(echo "$RESULT" | grep -oE "[0-9]+ passed")
    ok "Tests : $NB"
  else
    ko "Tests en echec ou non executables : $RESULT"
  fi
else
  warn "Tests non executes (.venv absent)"
fi
echo ""

# ============ F. FICHIERS CLES ============
echo "--- F. Fichiers cles du projet ---"
for f in docker-compose.yml Makefile pyproject.toml .env \
         api/main.py api/queries.py dashboard/app.py \
         infra/airflow/dags/atmofrance_pipeline.py \
         .github/workflows/ci.yml; do
  [ -f "$PROJET/$f" ] && ok "$f" || ko "$f MANQUANT"
done
echo ""

# ============ RESUME ============
echo "=============================================="
echo " RESUME DU DIAGNOSTIC"
echo "=============================================="
echo -e " ${VERT}OK   : $nb_ok${RESET}"
echo -e " ${JAUNE}WARN : $nb_warn${RESET}"
echo -e " ${ROUGE}KO   : $nb_ko${RESET}"
echo ""
if [ "$nb_ko" -eq 0 ]; then
  echo -e " ${VERT}>>> Le projet est PRET pour la demonstration. <<<${RESET}"
elif [ "$nb_ko" -le 2 ]; then
  echo -e " ${JAUNE}>>> Quelques points a corriger (voir KO ci-dessus). <<<${RESET}"
else
  echo -e " ${ROUGE}>>> Plusieurs problemes detectes. Lance reprendre_projet.sh. <<<${RESET}"
fi
echo "=============================================="
