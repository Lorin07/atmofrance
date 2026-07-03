#!/usr/bin/env bash
#
# AtmoFrance - Correctif du lanceur Airflow
#
# Probleme : en mode standalone, Airflow lance ses sous-processus (scheduler,
# api-server, triggerer, dag-processor) en appelant la commande 'airflow'
# depuis le PATH. Comme Airflow est dans un venv isole non active, la commande
# n'etait pas trouvee (FileNotFoundError).
#
# Solution : le lanceur ajoute le venv Airflow en tete du PATH.
#
set -euo pipefail

if [ ! -d .venv-airflow ]; then
  echo "ERREUR : .venv-airflow absent. Lance d'abord setup_phase10.sh"
  exit 1
fi

PROJET="$(pwd)"
AIRFLOW_VENV="$PROJET/.venv-airflow"
AIRFLOW_HOME="$PROJET/infra/airflow/home"

echo ">> Regeneration du lanceur Airflow (avec PATH corrige)..."
mkdir -p infra/airflow

cat > infra/airflow/lancer_airflow.sh << EOF
#!/usr/bin/env bash
# Lance Airflow en mode standalone (scheduler + serveur web + base).
#
# Le mode standalone lance ses sous-processus en appelant la commande 'airflow'
# depuis le PATH. On ajoute donc le venv Airflow en tete du PATH pour que ces
# sous-processus la trouvent, meme si le venv n'est pas active.
export AIRFLOW_HOME="$AIRFLOW_HOME"
export ATMOFRANCE_HOME="$PROJET"
export PATH="$AIRFLOW_VENV/bin:\$PATH"
cd "$PROJET"
exec "$AIRFLOW_VENV/bin/airflow" standalone
EOF
chmod +x infra/airflow/lancer_airflow.sh

echo "   Lanceur regenere : infra/airflow/lancer_airflow.sh"
echo ""
echo ">> Verification du contenu..."
grep -q "PATH=" infra/airflow/lancer_airflow.sh && echo "   PATH ajoute : OK"

echo ""
echo "=============================================="
echo " Correctif applique."
echo "=============================================="
echo " Relance Airflow :"
echo "   bash infra/airflow/lancer_airflow.sh"
echo ""
echo " Attends la ligne 'Airflow is ready' (~30 s au premier lancement),"
echo " puis ouvre http://localhost:8080"
echo " Identifiant : admin | Mot de passe : affiche dans la console"
echo " (ou dans infra/airflow/home/simple_auth_manager_passwords.json.generated)"
echo "=============================================="
