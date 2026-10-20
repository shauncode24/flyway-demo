.RECIPEPREFIX := >
ENV ?= dev
FW = docker compose run --rm flyway -configFiles=/flyway/conf/$(ENV).conf

up:
> docker compose up -d postgres

info:
> $(FW) info

validate:
> $(FW) validate

migrate:
> $(FW) migrate

repair:
> $(FW) repair

baseline:
> $(FW) baseline

migrate-all:
> for e in dev test prod; do $(MAKE) migrate ENV=$$e; done

history:
> docker compose exec postgres psql -U admin -d $(ENV)_db -c "SELECT installed_rank, version, description, type, checksum, installed_by, execution_time, success FROM flyway_schema_history ORDER BY installed_rank;"

psql:
> docker compose exec postgres psql -U admin -d $(ENV)_db

reset:
> docker compose run --rm flyway -configFiles=/flyway/conf/dev.conf clean
> docker compose run --rm flyway -configFiles=/flyway/conf/dev.conf migrate

down:
> docker compose down -v