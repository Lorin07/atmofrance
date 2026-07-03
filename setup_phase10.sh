#!/usr/bin/env bash
#
# AtmoFrance - Phase 10 : orchestration Airflow
#
# Approche robuste :
#   - Airflow est installe dans un environnement virtuel SEPARE (.venv-airflow)
#     pour ne PAS entrer en conflit avec les dependances du projet (.venv).
#   - Installation par la methode officielle avec fichier de contraintes,
#     seule methode garantie de ne pas casser l'environnement.
#   - Le DAG appelle les modules du projet via le .venv principal.
#
set -euo pipefail

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis le dossier atmofrance/"
  exit 1
fi
if [ ! -d .venv ]; then
  echo "ERREUR : environnement projet .venv absent"
  exit 1
fi

PROJET="$(pwd)"
AIRFLOW_VENV="$PROJET/.venv-airflow"
export AIRFLOW_HOME="$PROJET/infra/airflow/home"

echo ">> Phase 10 : orchestration Airflow"
echo "   Projet       : $PROJET"
echo "   Venv Airflow : $AIRFLOW_VENV (isole du venv projet)"
echo "   AIRFLOW_HOME : $AIRFLOW_HOME"

# ---------------------------------------------------------------------------
# 1. Environnement virtuel Airflow separe
# ---------------------------------------------------------------------------
if [ ! -d "$AIRFLOW_VENV" ]; then
  echo ">> Creation de l'environnement virtuel Airflow..."
  python3 -m venv "$AIRFLOW_VENV"
fi

PYVER=$("$AIRFLOW_VENV/bin/python" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "   Python detecte : $PYVER"

# Version d'Airflow : 3.2.2 est la premiere serie supportant officiellement
# Python 3.10 a 3.14 (les versions < 3.2 refusent Python 3.13). On l'utilise
# donc quelle que soit la version de Python installee, pour la robustesse.
AIRFLOW_VERSION="3.2.2"
CONSTRAINT="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYVER}.txt"

# Verification prealable : le fichier de contraintes existe-t-il pour ce Python ?
echo ">> Verification de la compatibilite (contraintes ${PYVER})..."
if ! curl -sfI "${CONSTRAINT}" >/dev/null 2>&1; then
  echo "   ATTENTION : pas de contraintes pour Python ${PYVER} en Airflow ${AIRFLOW_VERSION}."
  echo "   Installation sans contraintes (moins deterministe mais fonctionnelle)."
  CONSTRAINT=""
fi

echo ">> Installation d'Apache Airflow ${AIRFLOW_VERSION} (methode officielle avec contraintes)..."
echo "   (cette etape telecharge ~200 Mo, patienter 2-3 min)"
"$AIRFLOW_VENV/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1 || true
if [ -n "$CONSTRAINT" ]; then
  "$AIRFLOW_VENV/bin/pip" install --quiet \
    "apache-airflow==${AIRFLOW_VERSION}" \
    --constraint "${CONSTRAINT}"
else
  "$AIRFLOW_VENV/bin/pip" install --quiet "apache-airflow==${AIRFLOW_VERSION}"
fi

echo ">> Verification de l'installation Airflow..."
"$AIRFLOW_VENV/bin/python" -c "import airflow; print('   Airflow', airflow.__version__, 'installe')"

# ---------------------------------------------------------------------------
# 2. Configuration Airflow (dossier des DAGs, executor simple)
# ---------------------------------------------------------------------------
echo ">> Configuration d'Airflow..."
mkdir -p "$AIRFLOW_HOME"

# Initialiser la configuration si absente
if [ ! -f "$AIRFLOW_HOME/airflow.cfg" ]; then
  AIRFLOW_HOME="$AIRFLOW_HOME" "$AIRFLOW_VENV/bin/airflow" config list >/dev/null 2>&1 || true
fi

# Pointer le dossier des DAGs vers nos DAGs et desactiver les exemples.
DAGS_DIR="$PROJET/infra/airflow/dags"
python3 - "$AIRFLOW_HOME/airflow.cfg" "$DAGS_DIR" << 'PYEOF'
import sys, configparser, os
cfg_path, dags_dir = sys.argv[1], sys.argv[2]
if os.path.exists(cfg_path):
    cp = configparser.ConfigParser()
    cp.read(cfg_path)
    if cp.has_section("core"):
        cp.set("core", "dags_folder", dags_dir)
        cp.set("core", "load_examples", "False")
    with open(cfg_path, "w") as f:
        cp.write(f)
    print(f"   dags_folder -> {dags_dir}")
    print("   load_examples -> False")
else:
    print("   (airflow.cfg sera cree au premier lancement ; variable AIRFLOW_HOME utilisee)")
PYEOF

# ---------------------------------------------------------------------------
# 3. Fichier d'aide au lancement
# ---------------------------------------------------------------------------
cat > "$PROJET/infra/airflow/lancer_airflow.sh" << EOF
#!/usr/bin/env bash
# Lance Airflow en mode standalone (scheduler + serveur web + base).
export AIRFLOW_HOME="$AIRFLOW_HOME"
export ATMOFRANCE_HOME="$PROJET"
cd "$PROJET"
"$AIRFLOW_VENV/bin/airflow" standalone
EOF
chmod +x "$PROJET/infra/airflow/lancer_airflow.sh"

# ---------------------------------------------------------------------------
# 4. Validation du DAG (parsing)
# ---------------------------------------------------------------------------
echo ""
echo ">> Validation du DAG atmofrance_pipeline..."
AIRFLOW_HOME="$AIRFLOW_HOME" ATMOFRANCE_HOME="$PROJET" \
  "$AIRFLOW_VENV/bin/python" -c "
import sys
sys.path.insert(0, '$DAGS_DIR')
import atmofrance_pipeline as m
print('   DAG', m.dag.dag_id, ':', len(m.dag.tasks), 'taches')
print('   Taches :', [t.task_id for t in m.dag.tasks])
" 2>/dev/null

echo ""
echo "=============================================="
echo " Phase 10 installee."
echo "=============================================="
echo " Lance Airflow (dans un terminal dedie) :"
echo "   bash infra/airflow/lancer_airflow.sh"
echo ""
echo " Au premier lancement, Airflow affiche dans la console un identifiant"
echo " et un mot de passe 'admin'. Ouvre ensuite :"
echo "   http://localhost:8080"
echo ""
echo " Le DAG 'atmofrance_pipeline' y sera visible. Active-le et declenche-le."
echo " NB : le socle Docker (make up) doit tourner pour que les taches"
echo "      Spark/Kafka/Postgres fonctionnent."
echo "=============================================="
