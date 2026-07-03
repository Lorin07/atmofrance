# AtmoFrance

Plateforme d'ingenierie de donnees temps reel pour la surveillance de la qualite de l'air en France et l'analyse de son impact sanitaire.

Le systeme ingere les mesures horaires des stations de surveillance nationales, les croise avec des donnees meteorologiques, geographiques et demographiques, detecte les depassements de seuils reglementaires et predit les pics de pollution a 24 heures. L'ensemble est expose via une API REST et un tableau de bord cartographique interactif.

## Probleme traite

La pollution atmospherique est la premiere cause environnementale de mortalite en Europe. Les donnees existent mais restent dispersees et peu exploitees en vue analytique. AtmoFrance construit une chaine complete, de l'ingestion temps reel a la restitution decisionnelle, pour transformer ces mesures en information sanitaire actionnable.

## Architecture

Architecture Lakehouse Medallion (Bronze / Silver / Gold) combinant traitement en flux et en lot.

| Couche | Technologie | Role |
|--------|-------------|------|
| Ingestion streaming | Kafka | Flux temps reel des mesures et de la meteo |
| Ingestion batch | Python + Spark | Chargement de l'historique massif |
| Traitement distribue | Spark Structured Streaming | Nettoyage, enrichissement, agregation |
| Datalake | MinIO (S3-compatible) | Zones Bronze / Silver / Gold en Parquet |
| Stockage relationnel + geo | PostgreSQL + PostGIS | Agregats Gold et referentiel geographique |
| Stockage NoSQL | MongoDB | Releves bruts semi-structures |
| Orchestration | Airflow | DAGs batch, qualite et entrainement ML |
| Qualite | Great Expectations | Porte de qualite avant la zone Gold |
| API | FastAPI | Exposition des KPIs, stations et alertes |
| Restitution | Streamlit | Tableau de bord cartographique interactif |
| ML | scikit-learn / XGBoost | Prevision de pollution a 24 h |

Voir docs/architecture.md pour le detail.

## Sources de donnees

Toutes les sources sont publiques et sous licence ouverte. Voir docs/data-sources.md.

- Geod'Air / LCSQA : mesures horaires temps reel (6 polluants, ~600 stations)
- Geod'Air historique : archive depuis 2013
- Open-Meteo : donnees meteorologiques
- INSEE / IGN : population et contours geographiques

## Demarrage rapide

Prerequis : Docker et Docker Compose.

```bash
cp .env.example .env      # ajuster les mots de passe
make up                   # demarre le socle
make ps                   # verifie l'etat des services
```

Interfaces disponibles une fois le socle demarre :

- Console MinIO : http://localhost:9001
- PostgreSQL : localhost:5432
- MongoDB : localhost:27017
- Kafka : localhost:29092 (depuis l'hote)

## Structure du depot

```
atmofrance/
├── docker-compose.yml   Orchestration du stack
├── infra/               Configuration des services (Kafka, Postgres, Airflow, etc.)
├── ingestion/           Producteurs de flux et chargements batch
├── processing/          Traitements Spark et controles qualite
├── ml/                  Entrainement et evaluation du modele predictif
├── api/                 API REST FastAPI
├── dashboard/           Tableau de bord Streamlit
├── tests/               Tests unitaires et d'integration
└── docs/                Documentation et decisions d'architecture
```
