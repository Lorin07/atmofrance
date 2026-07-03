#!/usr/bin/env bash
#
# AtmoFrance - Correctif Phase 6 : psycopg2 -> psycopg3 (compatible Python 3.13)
# A lancer depuis le dossier atmofrance/
#
set -euo pipefail

if [ ! -d .venv ]; then
  echo "ERREUR : environnement .venv absent"
  exit 1
fi

echo ">> Correctif : remplacement de psycopg2 par psycopg3 (wheels Python 3.13)"

# 1. Corriger db.py
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

# 2. Corriger requirements.txt (retirer psycopg2, ajouter psycopg3)
echo ">> Correction des dependances..."
# Retire les lignes psycopg2 existantes
sed -i '/psycopg2/d' ingestion/requirements.txt
# Ajoute psycopg3 si absent
grep -q "psycopg\[binary\]" ingestion/requirements.txt 2>/dev/null || \
  sed -i 's/^pymongo==4.7.2/psycopg[binary]==3.2.1\npymongo==4.7.2/' ingestion/requirements.txt
# Filet de securite : si pymongo n'etait pas la, on ajoute les deux
grep -q "psycopg\[binary\]" ingestion/requirements.txt 2>/dev/null || cat >> ingestion/requirements.txt << 'EOF'

# Bases de donnees
psycopg[binary]==3.2.1
pymongo==4.7.2
EOF

# 3. Installer psycopg3 + pymongo
echo ">> Installation de psycopg[binary] et pymongo..."
.venv/bin/pip install --quiet "psycopg[binary]==3.2.1" pymongo==4.7.2

echo ""
echo ">> Verification de l'import..."
.venv/bin/python -c "import psycopg; import pymongo; print('psycopg', psycopg.__version__, '+ pymongo', pymongo.__version__, 'OK')"

echo ""
echo "=============================================="
echo " Correctif applique."
echo "=============================================="
echo " Relance maintenant :"
echo "   source .venv/bin/activate"
echo "   python -m ingestion.load_stations"
echo "=============================================="
