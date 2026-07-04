#!/usr/bin/env bash
#
# AtmoFrance - REPRISE DU PROJET DE A A Z
# ========================================
# A lancer apres un clonage du depot, ou sur une machine neuve.
# Reconstruit TOUT le projet et le peuple avec des donnees reelles.
#
# Etapes (expliquees au fur et a mesure) :
#   1. Verification des prerequis
#   2. Creation de l'environnement Python principal (.venv)
#   3. Creation de l'environnement Airflow isole (.venv-airflow)
#   4. Demarrage du socle Docker
#   5. Execution du pipeline complet (donnees reelles)
#   6. Verification finale
#
# Duree approximative : 15-25 min (selon la connexion, Spark telecharge
# ses connecteurs, Airflow ~200 Mo).
#
set -uo pipefail

PROJET="$(pwd)"
VENV="$PROJET/.venv/bin/python"
DATE_DEMO="${1:-2026-07-01}"   # date des donnees a ingerer (defaut : 1er juillet 2026)

echo "=============================================="
echo " AtmoFrance - Reprise du projet de A a Z"
echo "=============================================="
echo " Dossier : $PROJET"
echo " Date des donnees a ingerer : $DATE_DEMO"
echo "=============================================="
echo ""

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis la racine du projet atmofrance/"
  exit 1
fi

# ============ ETAPE 1 : PREREQUIS ============
echo ">> ETAPE 1/6 : Verification des prerequis"
echo "   (Docker, Docker Compose, Python 3.13, Java 17)"
echo ""

erreur_prereq=false
if ! command -v docker >/dev/null 2>&1; then
  echo "   ERREUR : Docker n'est pas installe."
  erreur_prereq=true
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "   ERREUR : Docker Compose n'est pas disponible."
  erreur_prereq=true
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "   ERREUR : Python 3 n'est pas installe."
  erreur_prereq=true
fi
PYV=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "?")
echo "   Python detecte : $PYV"
if ! command -v java >/dev/null 2>&1; then
  echo "   ATTENTION : Java non detecte. Spark en aura besoin (Java 17 recommande)."
fi

if $erreur_prereq; then
  echo ""
  echo "   Corrige les prerequis manquants avant de continuer."
  exit 1
fi
echo "   Prerequis OK."
echo ""

# ============ ETAPE 2 : VENV PRINCIPAL ============
echo ">> ETAPE 2/6 : Environnement Python principal (.venv)"
echo "   On cree un environnement isole et on installe les dependances."
echo "   REGLE : pas de version epinglee sur les paquets a compilation native"
echo "   (sinon echec sur Python 3.13)."
echo ""

if [ ! -d .venv ]; then
  python3 -m venv .venv
  echo "   .venv cree."
fi
.venv/bin/pip install --quiet --upgrade pip

echo "   Installation des dependances du projet..."
.venv/bin/pip install --quiet \
  "kafka-python-ng" \
  "python-dotenv" \
  "minio" \
  "psycopg[binary]" \
  "pymongo" \
  "pyspark==3.5.1" \
  "fastapi>=0.115" \
  "uvicorn>=0.30" \
  "streamlit" \
  "folium" \
  "streamlit-folium" \
  "plotly" \
  "pandas" \
  "requests" \
  "pytest" \
  "ruff"

echo "   Verification des imports cles..."
for mod in kafka psycopg pymongo pyspark fastapi streamlit folium; do
  .venv/bin/python -c "import $mod" 2>/dev/null && echo "     $mod OK" || echo "     $mod ECHEC"
done
echo ""

# ============ ETAPE 3 : VENV AIRFLOW (ISOLE) ============
echo ">> ETAPE 3/6 : Environnement Airflow isole (.venv-airflow)"
echo "   Airflow est installe SEPAREMENT pour ne pas casser les dependances"
echo "   du projet. Methode officielle avec fichier de contraintes."
echo ""

if [ ! -d .venv-airflow ]; then
  python3 -m venv .venv-airflow
  echo "   .venv-airflow cree."
fi
AF_PYVER=$(.venv-airflow/bin/python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
AIRFLOW_VERSION="3.2.2"
CONSTRAINT="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${AF_PYVER}.txt"
.venv-airflow/bin/pip install --quiet --upgrade pip
echo "   Installation d'Airflow ${AIRFLOW_VERSION} (peut prendre 2-3 min)..."
if curl -sfI "$CONSTRAINT" >/dev/null 2>&1; then
  .venv-airflow/bin/pip install --quiet "apache-airflow==${AIRFLOW_VERSION}" --constraint "$CONSTRAINT"
else
  .venv-airflow/bin/pip install --quiet "apache-airflow==${AIRFLOW_VERSION}"
fi
.venv-airflow/bin/python -c "import airflow; print('   Airflow', airflow.__version__, 'installe')" 2>/dev/null || echo "   ATTENTION : Airflow non verifiable"
echo ""

# ============ ETAPE 4 : SOCLE DOCKER ============
echo ">> ETAPE 4/6 : Demarrage du socle Docker"
echo "   Lance les 5 services : PostgreSQL, MongoDB, MinIO, Kafka, Zookeeper."
echo ""
make up
echo "   Attente de 25 secondes que les services soient prets..."
sleep 25
docker compose ps
echo ""

# ============ ETAPE 5 : PIPELINE COMPLET ============
echo ">> ETAPE 5/6 : Execution du pipeline complet"
echo "   Ingestion -> Bronze -> Silver -> Gold -> bases."
echo "   (Spark telecharge ses connecteurs au 1er lancement, patience.)"
echo ""

echo "   [5.1] Ingestion : telechargement + publication dans Kafka..."
"$VENV" -m ingestion.producers.geodair_producer --date "$DATE_DEMO" --rate 500

echo "   [5.2] Consommation : Kafka -> Bronze..."
"$VENV" -m ingestion.consumers.bronze_consumer --timeout 30

echo "   [5.3] Bronze -> Silver (Spark : nettoyage, dedoublonnage)..."
"$VENV" -m processing.spark.bronze_to_silver

echo "   [5.4] Silver -> Gold (Spark : indices, moyennes)..."
"$VENV" -m processing.spark.silver_to_gold

echo "   [5.5] Referentiel stations (geocodage -> PostGIS + MongoDB)..."
"$VENV" -m ingestion.load_stations

echo "   [5.6] Gold -> PostgreSQL (Spark JDBC)..."
"$VENV" -m processing.spark.gold_to_postgres
echo ""

# ============ ETAPE 6 : VERIFICATION ============
echo ">> ETAPE 6/6 : Verification finale"
echo ""
NB_IND=$(docker exec atmo-postgres psql -U atmo -d atmofrance -tAc "SELECT COUNT(*) FROM gold_indice_journalier;" 2>/dev/null | tr -d ' ')
NB_DOC=$(docker exec atmo-mongo mongosh -u atmo -p change_me --authenticationDatabase admin atmofrance_raw --quiet --eval "db.stations.countDocuments()" 2>/dev/null | tr -d ' \r\n')
echo "   Indices dans PostgreSQL : ${NB_IND:-0}"
echo "   Documents dans MongoDB  : ${NB_DOC:-0}"
echo ""

echo "=============================================="
echo " REPRISE TERMINEE"
echo "=============================================="
echo " Le projet est reconstruit et peuple."
echo ""
echo " Pour lancer la demo :"
echo "   bash lancer_demo.sh"
echo ""
echo " Pour verifier l'etat complet :"
echo "   bash diagnostic.sh"
echo "=============================================="
