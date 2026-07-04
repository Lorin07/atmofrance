#!/usr/bin/env bash
#
# AtmoFrance - Script de DEMONSTRATION (jour J)
# ==============================================
# Ce script prepare et lance la demo SANS rejouer tout le pipeline.
# Il suppose que les donnees sont deja presentes (pipeline deja execute).
#
# Ce qu'il fait :
#   1. Verifie que le socle Docker tourne (le demarre sinon)
#   2. Verifie que les donnees sont presentes
#   3. Lance l'API en arriere-plan
#   4. Lance le dashboard en arriere-plan
#   5. Affiche les URLs a ouvrir
#
# Pour ARRETER la demo : bash lancer_demo.sh stop
#
set -uo pipefail

PROJET="/home/pourtoi/taf/bahut/atmofrance"
VENV="$PROJET/.venv/bin/python"
LOG_DIR="$PROJET/.demo_logs"
API_PORT=8000
DASH_PORT=8501

cd "$PROJET" || { echo "ERREUR : projet introuvable a $PROJET"; exit 1; }

# ============ MODE STOP ============
if [ "${1:-}" = "stop" ]; then
  echo ">> Arret de la demo..."
  pkill -f "uvicorn api.main:app" 2>/dev/null && echo "   API arretee" || echo "   API n'etait pas active"
  pkill -f "streamlit run dashboard/app.py" 2>/dev/null && echo "   Dashboard arrete" || echo "   Dashboard n'etait pas actif"
  echo ">> Demo arretee. (Le socle Docker reste actif ; pour l'arreter : make down)"
  exit 0
fi

mkdir -p "$LOG_DIR"

echo "=============================================="
echo " AtmoFrance - Preparation de la demonstration"
echo "=============================================="
echo ""

# ============ 1. SOCLE DOCKER ============
echo ">> [1/4] Verification du socle Docker..."
if ! docker compose ps 2>/dev/null | grep -q "atmo-postgres"; then
  echo "   Le socle n'est pas demarre. Demarrage en cours..."
  make up
  echo "   Attente de 25 secondes que les services soient prets..."
  sleep 25
else
  # Verifier que les services cles sont "healthy" ou "running"
  services_ok=true
  for svc in atmo-postgres atmo-mongo atmo-minio atmo-kafka; do
    if ! docker compose ps 2>/dev/null | grep "$svc" | grep -qE "healthy|running|Up"; then
      services_ok=false
      echo "   ATTENTION : $svc ne semble pas actif"
    fi
  done
  if $services_ok; then
    echo "   OK - les services Docker tournent."
  else
    echo "   Redemarrage du socle par precaution..."
    make up
    sleep 15
  fi
fi
echo ""

# ============ 2. DONNEES PRESENTES ? ============
echo ">> [2/4] Verification de la presence des donnees..."
NB_INDICES=$(docker exec atmo-postgres psql -U atmo -d atmofrance -tAc \
  "SELECT COUNT(*) FROM gold_indice_journalier;" 2>/dev/null | tr -d ' ')
if [ -n "$NB_INDICES" ] && [ "$NB_INDICES" -gt 0 ] 2>/dev/null; then
  echo "   OK - $NB_INDICES indices presents dans PostgreSQL."
else
  echo "   ATTENTION : aucune donnee dans PostgreSQL !"
  echo "   Le pipeline n'a peut-etre pas ete execute."
  echo "   -> Lance d'abord : bash reprendre_projet.sh  (ou le pipeline manuel)"
  echo "   La demo peut continuer mais l'API renverra des resultats vides."
  echo ""
  read -p "   Continuer quand meme ? (o/N) " reponse
  if [ "$reponse" != "o" ] && [ "$reponse" != "O" ]; then
    echo "   Demo annulee."
    exit 1
  fi
fi
echo ""

# ============ 3. LANCER L'API ============
echo ">> [3/4] Lancement de l'API (port $API_PORT)..."
# Arreter une eventuelle instance precedente
pkill -f "uvicorn api.main:app" 2>/dev/null && sleep 2
# Lancer avec le Python du venv (IMPORTANT : chemin explicite pour eviter pyenv)
nohup "$VENV" -m uvicorn api.main:app --host 0.0.0.0 --port $API_PORT > "$LOG_DIR/api.log" 2>&1 &
echo "   Demarrage de l'API..."
# Attendre que l'API reponde (max 20s)
for i in $(seq 1 20); do
  if curl -s "http://localhost:$API_PORT/health" >/dev/null 2>&1; then
    echo "   OK - API accessible sur http://localhost:$API_PORT"
    break
  fi
  sleep 1
  if [ "$i" = "20" ]; then
    echo "   ATTENTION : l'API met du temps a repondre. Voir $LOG_DIR/api.log"
  fi
done
echo ""

# ============ 4. LANCER LE DASHBOARD ============
echo ">> [4/4] Lancement du dashboard (port $DASH_PORT)..."
pkill -f "streamlit run dashboard/app.py" 2>/dev/null && sleep 2
nohup "$VENV" -m streamlit run dashboard/app.py \
  --server.port $DASH_PORT --server.headless true > "$LOG_DIR/dashboard.log" 2>&1 &
echo "   Demarrage du dashboard..."
sleep 8
echo "   OK - dashboard en cours de demarrage."
echo ""

# ============ RECAPITULATIF ============
echo "=============================================="
echo " DEMONSTRATION PRETE"
echo "=============================================="
echo ""
echo " Ouvre ces adresses dans ton navigateur :"
echo ""
echo "   Dashboard (carte)   ->  http://localhost:$DASH_PORT"
echo "   API (Swagger)       ->  http://localhost:$API_PORT/docs"
echo ""
echo " Pour Airflow (dans un terminal SEPARE si besoin) :"
echo "   bash infra/airflow/lancer_airflow.sh"
echo "   puis  ->  http://localhost:8080"
echo ""
echo " Pour ARRETER la demo :"
echo "   bash lancer_demo.sh stop"
echo ""
echo " Logs en cas de souci :"
echo "   API       : $LOG_DIR/api.log"
echo "   Dashboard : $LOG_DIR/dashboard.log"
echo "=============================================="
