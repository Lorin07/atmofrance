#!/usr/bin/env bash
# Lance Airflow en mode standalone (scheduler + serveur web + base).
#
# Le mode standalone lance ses sous-processus en appelant la commande 'airflow'
# depuis le PATH. On ajoute donc le venv Airflow en tete du PATH pour que ces
# sous-processus la trouvent, meme si le venv n'est pas active.
export AIRFLOW_HOME="/home/pourtoi/taf/bahut/atmofrance/infra/airflow/home"
export ATMOFRANCE_HOME="/home/pourtoi/taf/bahut/atmofrance"
export PATH="/home/pourtoi/taf/bahut/atmofrance/.venv-airflow/bin:$PATH"
cd "/home/pourtoi/taf/bahut/atmofrance"
exec "/home/pourtoi/taf/bahut/atmofrance/.venv-airflow/bin/airflow" standalone
