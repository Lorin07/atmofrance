# CHECKLIST DÉMONSTRATION — PROJET ATMOFRANCE
### À imprimer et suivre avant la soutenance

---

## PARTIE 1 — LA VEILLE DE LA SOUTENANCE

Objectif : tout préparer pour que le jour J, il n'y ait qu'à lancer une commande.

### ☐ 1. Vérifier que la machine est prête
- ☐ Docker Desktop / Docker démarré
- ☐ Batterie chargée + chargeur dans le sac
- ☐ Connexion internet testée (le pipeline télécharge les données)

### ☐ 2. Reconstruire le projet si nécessaire
Si le projet a été déplacé, cloné, ou si les données ont été effacées :
```bash
cd /home/pourtoi/taf/bahut/atmofrance
bash reprendre_projet.sh
```
Attendre la fin (15-25 min). Vérifier le message « REPRISE TERMINÉE » avec des indices > 0.

### ☐ 3. Lancer le diagnostic complet
```bash
bash diagnostic.sh
```
- ☐ Objectif : **0 KO** (que des OK, quelques WARN tolérés)
- ☐ Si des KO : les corriger la veille (pas le jour J !)

### ☐ 4. Faire un essai complet de la démo
```bash
bash lancer_demo.sh
```
- ☐ Ouvrir http://localhost:8501 → la carte s'affiche
- ☐ Ouvrir http://localhost:8000/docs → Swagger s'affiche
- ☐ Tester Airflow : `bash infra/airflow/lancer_airflow.sh` → http://localhost:8080
- ☐ Noter le mot de passe Airflow :
```bash
cat infra/airflow/home/simple_auth_manager_passwords.json.generated
```
Mot de passe Airflow : _______________________

### ☐ 5. Arrêter proprement après l'essai
```bash
bash lancer_demo.sh stop
```

### ☐ 6. Préparer les onglets navigateur (optionnel)
Préparer les favoris ou onglets :
- ☐ http://localhost:8501 (dashboard)
- ☐ http://localhost:8000/docs (API)
- ☐ http://localhost:8080 (Airflow)
- ☐ http://localhost:9001 (MinIO — login atmo / change_me_minio)
- ☐ https://github.com/Lorin07/atmofrance (le code)

---

## PARTIE 2 — LE JOUR J (avant de passer)

### ☐ 1. Démarrer Docker
Ouvrir Docker et attendre qu'il soit prêt.

### ☐ 2. Lancer le diagnostic (2 min)
```bash
cd /home/pourtoi/taf/bahut/atmofrance && bash diagnostic.sh
```
- ☐ Vérifier : 0 KO

### ☐ 3. Lancer la démo
```bash
bash lancer_demo.sh
```
- ☐ Attendre le message « DÉMONSTRATION PRÊTE »

### ☐ 4. Ouvrir les onglets
- ☐ Dashboard : http://localhost:8501
- ☐ Swagger : http://localhost:8000/docs

### ☐ 5. (Si démo Airflow prévue) Terminal séparé
```bash
bash infra/airflow/lancer_airflow.sh
```
- ☐ http://localhost:8080 (admin + mot de passe noté la veille)

---

## PARTIE 3 — FIL CONDUCTEUR DE LA DÉMO (suggestion)

Ordre suggéré pour raconter le projet au jury :

1. **Le problème** (30s) : la qualité de l'air, données publiques dispersées.

2. **L'architecture** (1 min) : montrer le schéma médaillon Bronze/Silver/Gold.

3. **Les données brutes** → **MinIO** (http://localhost:9001) :
   - Montrer les 3 buckets bronze/silver/gold
   - Montrer le partitionnement par date et les fichiers Parquet

4. **Le stockage structuré** → **terminal** :
   - PostgreSQL : `docker exec -it atmo-postgres psql -U atmo -d atmofrance -c "\dt"`
   - MongoDB : un document station

5. **L'API** → http://localhost:8000/docs :
   - Montrer les routes, tester /stats en direct

6. **Le résultat** → http://localhost:8501 :
   - La carte de France, les KPI, les filtres

7. **L'industrialisation** → **Airflow** (http://localhost:8080) :
   - Le DAG, les 5 tâches, l'historique des exécutions en vert

8. **La qualité** → **terminal** :
   - Les 21 tests : `.venv/bin/python -m pytest tests/unit/ -v`
   - Le code sur GitHub

9. **Conclusion** (30s) : bilan, évolutions (ML de prévision, cloud).

---

## EN CAS DE PROBLÈME LE JOUR J

| Symptôme | Solution rapide |
|----------|-----------------|
| L'API ne démarre pas | `cat .demo_logs/api.log` pour voir l'erreur |
| « No module named X » | Environnement pas activé → les scripts utilisent `.venv/bin/python` explicite, relancer le script |
| Le dashboard est vide | Vérifier que l'API tourne (http://localhost:8000/health) |
| Port déjà utilisé | `bash lancer_demo.sh stop` puis relancer |
| Airflow ne démarre pas | Vérifier le PATH dans lancer_airflow.sh |
| Données absentes | `bash reprendre_projet.sh` (mais long — à faire la veille !) |
| Docker service KO | `make down` puis `make up`, attendre 30s |

**Règle d'or** : ne jamais taper `uvicorn` ou `python` tout court → toujours passer par les scripts (qui utilisent le bon environnement).

---

## CONTACTS ET ACCÈS UTILES

| Ressource | Accès |
|-----------|-------|
| Dashboard | http://localhost:8501 |
| API Swagger | http://localhost:8000/docs |
| Airflow | http://localhost:8080 (admin / voir fichier généré) |
| MinIO | http://localhost:9001 (atmo / change_me_minio) |
| GitHub | https://github.com/Lorin07/atmofrance |
| Dossier projet | /home/pourtoi/taf/bahut/atmofrance |

---

*Checklist AtmoFrance — à conserver avec soi le jour de la soutenance.*
