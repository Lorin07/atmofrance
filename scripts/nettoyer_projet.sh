#!/usr/bin/env bash
#
# AtmoFrance - Nettoyage du projet pour le rendre livrable
#
# Principe de securite : on ARCHIVE (deplace) plutot que supprimer,
# sauf pour les doublons averes dont on verifie d'abord l'original.
#
set -euo pipefail

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis le dossier atmofrance/"
  exit 1
fi

echo ">> Nettoyage du projet AtmoFrance"
echo ""

# ---------------------------------------------------------------------------
# 1. Dossier d'archive (filet de securite)
# ---------------------------------------------------------------------------
mkdir -p _archive/scripts_setup
echo ">> Dossier _archive/ cree (filet de securite)."

# ---------------------------------------------------------------------------
# 2. Archiver les scripts de setup et correctifs temporaires
# ---------------------------------------------------------------------------
echo ">> Archivage des scripts temporaires..."
for f in setup_phase4.sh setup_phase4b.sh setup_phase5.sh setup_phase6.sh \
         setup_phase7.sh setup_phase8.sh setup_phase9.sh setup_phase10.sh \
         setup_phase11.sh setup_phase101.sh \
         fix_airflow_launcher.sh fix_dashboard_deps.sh fix_phase6_psycopg.sh \
         fix_psycopg_robust.sh init_git.sh install_dag.sh; do
  if [ -f "$f" ]; then
    mv "$f" _archive/scripts_setup/
    echo "   archive : $f"
  fi
done

# ---------------------------------------------------------------------------
# 3. Supprimer les doublons a la racine (APRES verification de l'original)
# ---------------------------------------------------------------------------
echo ""
echo ">> Verification et suppression des doublons a la racine..."

# atmofrance_pipeline.py : l'original doit etre dans infra/airflow/dags/
if [ -f "atmofrance_pipeline.py" ]; then
  if [ -f "infra/airflow/dags/atmofrance_pipeline.py" ]; then
    # Verifier qu'ils sont identiques ou que l'original est valide
    mv "atmofrance_pipeline.py" _archive/
    echo "   doublon archive : atmofrance_pipeline.py (original present dans infra/airflow/dags/)"
  else
    echo "   ATTENTION : atmofrance_pipeline.py a la racine mais PAS dans infra/airflow/dags/ !"
    echo "   -> je le DEPLACE au bon endroit au lieu de l'archiver."
    mkdir -p infra/airflow/dags
    mv "atmofrance_pipeline.py" infra/airflow/dags/
    echo "   deplace vers infra/airflow/dags/"
  fi
fi

# ci.yml : l'original doit etre dans .github/workflows/
if [ -f "ci.yml" ]; then
  if [ -f ".github/workflows/ci.yml" ]; then
    mv "ci.yml" _archive/
    echo "   doublon archive : ci.yml (original present dans .github/workflows/)"
  else
    echo "   ATTENTION : ci.yml a la racine mais PAS dans .github/workflows/ !"
    echo "   -> je le DEPLACE au bon endroit."
    mkdir -p .github/workflows
    mv "ci.yml" .github/workflows/
    echo "   deplace vers .github/workflows/"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Nettoyer les caches Python
# ---------------------------------------------------------------------------
echo ""
echo ">> Nettoyage des caches..."
find . -type d -name "__pycache__" -not -path "./.venv/*" -not -path "./.venv-airflow/*" -exec rm -rf {} + 2>/dev/null || true
rm -rf .pytest_cache .ruff_cache 2>/dev/null || true
echo "   caches supprimes (__pycache__, .pytest_cache, .ruff_cache)"

# ---------------------------------------------------------------------------
# 5. Mettre a jour le .gitignore
# ---------------------------------------------------------------------------
echo ""
echo ">> Mise a jour du .gitignore..."
for regle in "_archive/" "__pycache__/" ".pytest_cache/" ".ruff_cache/"; do
  if ! grep -qxF "$regle" .gitignore 2>/dev/null; then
    echo "$regle" >> .gitignore
    echo "   ajoute au .gitignore : $regle"
  fi
done

# ---------------------------------------------------------------------------
# 6. Verifier les dossiers data/ docs/ ml/ (informations)
# ---------------------------------------------------------------------------
echo ""
echo ">> Etat des dossiers a verifier manuellement :"
for d in data docs ml; do
  if [ -d "$d" ]; then
    nb=$(find "$d" -type f 2>/dev/null | wc -l)
    echo "   $d/ : $nb fichier(s)"
  fi
done

echo ""
echo "=============================================="
echo " Nettoyage termine."
echo "=============================================="
echo ""
echo " Structure du projet apres nettoyage :"
ls -1 --group-directories-first | grep -v "^_archive$" | grep -v "^\.venv"
echo ""
echo " Les scripts temporaires sont dans _archive/ (exclu de git)."
echo " Si tout fonctionne, tu pourras supprimer _archive/ definitivement."
echo "=============================================="
