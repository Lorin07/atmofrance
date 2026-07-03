.PHONY: help up down logs ps clean psql mongo-shell test lint

help:
	@echo "AtmoFrance - commandes disponibles :"
	@echo "  make up          Demarre le socle (postgres, mongo, minio, kafka)"
	@echo "  make down        Arrete les conteneurs"
	@echo "  make logs        Affiche les logs en continu"
	@echo "  make ps          Liste les conteneurs et leur etat"
	@echo "  make clean       Arrete et supprime les volumes (RESET total)"
	@echo "  make psql        Ouvre un shell PostgreSQL"
	@echo "  make mongo-shell Ouvre un shell MongoDB"
	@echo "  make test        Lance les tests pytest"
	@echo "  make lint        Verifie le style du code (ruff)"

up:
	docker compose up -d
	@echo "Socle demarre. Console MinIO : http://localhost:9001"

down:
	docker compose down

logs:
	docker compose logs -f

ps:
	docker compose ps

clean:
	docker compose down -v
	@echo "Conteneurs et volumes supprimes."

psql:
	docker compose exec postgres psql -U $${POSTGRES_USER:-atmo} -d $${POSTGRES_DB:-atmofrance}

mongo-shell:
	docker compose exec mongo mongosh -u $${MONGO_USER:-atmo} -p $${MONGO_PASSWORD:-change_me}

test:
	pytest tests/ -v

lint:
	ruff check .
