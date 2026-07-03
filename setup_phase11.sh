#!/usr/bin/env bash
#
# AtmoFrance - Phase 11 : CI/CD GitHub Actions (tests + linter ruff)
# A lancer depuis le dossier atmofrance/
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

echo ">> Phase 11 : CI/CD GitHub Actions + ruff"

# ---------------------------------------------------------------------------
# 1. pyproject.toml (config ruff + pytest)
# ---------------------------------------------------------------------------
echo ">> Ecriture de pyproject.toml..."
cat > pyproject.toml << 'EOF'
[project]
name = "atmofrance"
version = "1.0.0"
description = "Plateforme d'ingenierie de donnees pour la surveillance de la qualite de l'air en France"
requires-python = ">=3.10"

[tool.ruff]
line-length = 100
src = ["ingestion", "processing", "api", "dashboard", "tests"]
exclude = [
    ".venv",
    ".venv-airflow",
    "infra/airflow/home",
    "__pycache__",
    "*.egg-info",
]

[tool.ruff.lint]
select = ["E", "W", "F", "I", "UP", "B"]
ignore = [
    "E501",
    "B008",
]

[tool.ruff.lint.per-file-ignores]
"__init__.py" = ["F401"]

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
python_functions = ["test_*"]
EOF

# ---------------------------------------------------------------------------
# 2. Workflow GitHub Actions
# ---------------------------------------------------------------------------
echo ">> Ecriture de .github/workflows/ci.yml..."
mkdir -p .github/workflows
cat > .github/workflows/ci.yml << 'EOF'
name: CI AtmoFrance

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]

jobs:
  qualite-et-tests:
    name: Qualite du code et tests unitaires
    runs-on: ubuntu-latest

    steps:
      - name: Recuperer le depot
        uses: actions/checkout@v4

      - name: Installer Python 3.13
        uses: actions/setup-python@v5
        with:
          python-version: "3.13"
          cache: pip

      - name: Installer les dependances
        run: |
          python -m pip install --upgrade pip
          pip install ruff pytest
          pip install pyspark kafka-python-ng python-dotenv

      - name: Verifier la qualite du code (ruff)
        run: ruff check ingestion processing api dashboard tests

      - name: Executer les tests unitaires (pytest)
        run: pytest tests/unit -v
EOF

# ---------------------------------------------------------------------------
# 3. requirements-dev.txt (outils de dev)
# ---------------------------------------------------------------------------
echo ">> Ecriture de requirements-dev.txt..."
cat > requirements-dev.txt << 'EOF'
# Outils de developpement et qualite
ruff
pytest
EOF

# ---------------------------------------------------------------------------
# 4. Installation de ruff dans le venv et correction automatique du code
# ---------------------------------------------------------------------------
echo ">> Installation de ruff..."
.venv/bin/pip install --quiet ruff pytest

echo ">> Correction automatique du code par ruff (imports, formatage)..."
.venv/bin/ruff check ingestion processing api dashboard tests --fix 2>&1 | tail -3 || true

echo ""
echo ">> Verification : ruff passe-t-il maintenant ?"
if .venv/bin/ruff check ingestion processing api dashboard tests 2>&1 | grep -q "All checks passed"; then
  echo "   All checks passed (ruff)"
else
  echo "   Quelques points restants (verifie ci-dessus, souvent corrigeables a la main)"
  .venv/bin/ruff check ingestion processing api dashboard tests 2>&1 | tail -10
fi

# ---------------------------------------------------------------------------
# 5. Verification : les 21 tests passent
# ---------------------------------------------------------------------------
echo ""
echo ">> Execution des 21 tests unitaires..."
.venv/bin/python -m pytest tests/unit/ -v 2>&1 | tail -28

echo ""
echo "=============================================="
echo " Phase 11 installee."
echo "=============================================="
echo " Le CI/CD se declenchera automatiquement quand tu pousseras sur GitHub."
echo ""
echo " Pour l'activer :"
echo "   git add ."
echo "   git commit -m \"Ajout CI/CD GitHub Actions + ruff\""
echo "   git push"
echo ""
echo " L'onglet 'Actions' de ton depot GitHub montrera le workflow s'executer"
echo " (installation, ruff, 21 tests). Un badge vert = tout passe."
echo "=============================================="
