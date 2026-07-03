#!/usr/bin/env bash
#
# AtmoFrance - Correctif robuste psycopg (PostgreSQL) pour Python 3.13 / miniconda
#
# Approche durable :
#   - on n'epingle PAS une version precise (les wheels binaires evoluent)
#   - on tente psycopg[binary] (wheel autoportant, embarque libpq)
#   - repli 1 : psycopg[binary] version la plus recente explicite
#   - repli 2 : libpq via conda + psycopg pur Python
#   - verification finale obligatoire : si l'import echoue, le script echoue
#
set -euo pipefail

if [ ! -d .venv ]; then
  echo "ERREUR : environnement .venv absent (lance depuis atmofrance/)"
  exit 1
fi

PY=.venv/bin/python
PIP=.venv/bin/pip

echo ">> Correctif psycopg : installation robuste (sans version fragile)"

# ---------------------------------------------------------------------------
# 1. Corriger db.py pour utiliser psycopg (v3)
# ---------------------------------------------------------------------------
echo ">> Correction de ingestion/db.py..."
cat > ingestion/db.py << 'PYEOF'
"""Connexions aux bases de donnees du projet AtmoFrance."""
import psycopg
from pymongo import MongoClient

from ingestion import config


def connexion_postgres():
    return psycopg.connect(
        host=config._get("POSTGRES_HOST_LOCAL", "localhost"),
        port=config._get("POSTGRES_PORT", "5432"),
        dbname=config._get("POSTGRES_DB", "atmofrance"),
        user=config._get("POSTGRES_USER", "atmo"),
        password=config._get("POSTGRES_PASSWORD", "change_me"),
    )


def client_mongo() -> MongoClient:
    hote = config._get("MONGO_HOST_LOCAL", "localhost")
    port = config._get("MONGO_PORT", "27017")
    user = config._get("MONGO_USER", "atmo")
    mdp = config._get("MONGO_PASSWORD", "change_me")
    uri = f"mongodb://{user}:{mdp}@{hote}:{port}/"
    return MongoClient(uri)


def base_mongo():
    client = client_mongo()
    nom_base = config._get("MONGO_DB", "atmofrance_raw")
    return client, client[nom_base]
PYEOF

# ---------------------------------------------------------------------------
# 2. Corriger requirements.txt (sans version epinglee pour psycopg)
# ---------------------------------------------------------------------------
echo ">> Mise a jour des dependances..."
sed -i '/psycopg/d' ingestion/requirements.txt
grep -q "pymongo" ingestion/requirements.txt 2>/dev/null || echo "pymongo==4.7.2" >> ingestion/requirements.txt
# Ajouter psycopg[binary] sans version (bonne pratique pour wheels binaires)
if ! grep -q "psycopg\[binary\]" ingestion/requirements.txt; then
  # Inserer juste avant pymongo pour rester lisible
  if grep -q "pymongo" ingestion/requirements.txt; then
    sed -i 's/^pymongo/psycopg[binary]\npymongo/' ingestion/requirements.txt
  else
    echo "psycopg[binary]" >> ingestion/requirements.txt
  fi
fi

# ---------------------------------------------------------------------------
# 3. Installation avec strategie de repli
# ---------------------------------------------------------------------------
$PIP install --quiet --upgrade pip >/dev/null 2>&1 || true

echo ">> Tentative 1 : psycopg[binary] (recommande)..."
if $PIP install --quiet "psycopg[binary]" pymongo 2>/dev/null; then
  echo "   installe."
else
  echo "   echec, tentative 2..."
  echo ">> Tentative 2 : derniere version explicite de psycopg[binary]..."
  if $PIP install --quiet "psycopg[binary]>=3.2" pymongo 2>/dev/null; then
    echo "   installe."
  else
    echo "   echec, tentative 3 (libpq via conda)..."
    echo ">> Tentative 3 : libpq systeme via conda + psycopg pur Python..."
    conda install -y -q libpq postgresql 2>/dev/null || \
      echo "   (conda indisponible, on continue)"
    $PIP install --quiet "psycopg" pymongo
  fi
fi

# ---------------------------------------------------------------------------
# 4. VERIFICATION OBLIGATOIRE : l'import doit reussir, sinon on echoue
# ---------------------------------------------------------------------------
echo ""
echo ">> Verification de l'installation..."
if $PY -c "import psycopg; import pymongo; print('   psycopg', psycopg.__version__, '+ pymongo', pymongo.__version__, 'OK')"; then
  echo ""
  echo ">> Verification de la connexion PostgreSQL (le socle doit tourner)..."
  if $PY -c "
from ingestion import db
try:
    conn = db.connexion_postgres()
    cur = conn.cursor()
    cur.execute('SELECT postgis_version();')
    v = cur.fetchone()[0]
    print('   PostgreSQL/PostGIS accessible, PostGIS', v.split()[0])
    conn.close()
except Exception as e:
    print('   AVERTISSEMENT : connexion impossible (le socle Docker tourne-t-il ?)')
    print('   Detail :', str(e)[:120])
"; then
    :
  fi
  echo ""
  echo "=============================================="
  echo " Correctif applique et verifie avec succes."
  echo "=============================================="
  echo " Relance maintenant :"
  echo "   source .venv/bin/activate"
  echo "   python -m ingestion.load_stations"
  echo "=============================================="
else
  echo ""
  echo "ECHEC : psycopg n'a pas pu etre installe. Envoie-moi la sortie complete."
  exit 1
fi
