#!/usr/bin/env bash
#
# AtmoFrance - Correction ruff finale + initialisation du depot Git
#
set -euo pipefail

if [ ! -f docker-compose.yml ]; then
  echo "ERREUR : lance ce script depuis le dossier atmofrance/"
  exit 1
fi

echo ">> Etape 1 : correction ruff restante (zip strict)..."
# Ajoute strict=False au zip de l'API (comportement identique, mais explicite)
if grep -q "zip(colonnes, ligne))" api/queries.py 2>/dev/null; then
  sed -i 's/zip(colonnes, ligne))/zip(colonnes, ligne, strict=False))/g' api/queries.py
  echo "   api/queries.py corrige."
else
  echo "   deja corrige (ou motif absent)."
fi

echo ""
echo ">> Verification ruff sur tout le projet..."
if [ -x .venv/bin/ruff ]; then
  if .venv/bin/ruff check ingestion processing api dashboard tests 2>&1 | grep -q "All checks passed"; then
    echo "   All checks passed (ruff)"
  else
    echo "   Points restants :"
    .venv/bin/ruff check ingestion processing api dashboard tests 2>&1 | grep -vE "E902" | tail -12
  fi
fi

echo ""
echo ">> Etape 2 : initialisation du depot Git..."

# Verifier que git est installe
if ! command -v git >/dev/null 2>&1; then
  echo "ERREUR : git n'est pas installe. Installe-le avec : sudo apt install git"
  exit 1
fi

# Initialiser le depot si absent
if [ ! -d .git ]; then
  git init -b main
  echo "   Depot Git initialise (branche main)."
else
  echo "   Depot Git deja present."
fi

# Verifier la configuration utilisateur git (nom + email)
GIT_NAME=$(git config user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config user.email 2>/dev/null || echo "")
if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
  echo ""
  echo "   ATTENTION : identite Git non configuree."
  echo "   Configure-la (une seule fois) avec TES informations :"
  echo "     git config --global user.name \"Ton Nom\""
  echo "     git config --global user.email \"ton.email@example.com\""
  echo ""
fi

# Ajouter les fichiers (le .gitignore exclut venvs, donnees, secrets)
git add .
echo ""
echo ">> Fichiers qui seront versionnes (apercu) :"
git status --short | head -30
echo ""
NB_FICHIERS=$(git status --short | wc -l)
echo "   Total : $NB_FICHIERS fichiers a versionner"

echo ""
echo ">> Verification : aucun secret ni venv versionne ?"
if git status --short | grep -qE "\.venv|\.env$|postgres-data|minio-data"; then
  echo "   ATTENTION : des fichiers sensibles semblent inclus (a verifier ci-dessus)"
else
  echo "   OK : ni venv, ni .env, ni volumes de donnees (proteges par .gitignore)"
fi

echo ""
echo "=============================================="
echo " Depot Git pret."
echo "=============================================="
echo " Prochaines etapes (voir instructions detaillees)."
echo "=============================================="
