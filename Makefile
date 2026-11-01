.RECIPEPREFIX := >
ENV ?= dev
STAGE ?=
FW = docker compose run --rm flyway -configFiles=/flyway/conf/$(ENV).conf

up:
> docker compose up -d --build --wait postgres dashboard

info:
> $(FW) info

validate:
> $(FW) validate

migrate:
> $(FW) migrate

migrate-ooo:
> $(FW) migrate -outOfOrder=true

repair:
> $(FW) repair

baseline:
> $(FW) baseline -baselineVersion=8 -baselineDescription="Legacy database"

migrate-all:
> set -e; for e in dev test prod; do echo "=== Migrating $$e ==="; $(MAKE) migrate ENV=$$e; done

history:
> docker compose exec postgres psql -U admin -d $(ENV)_db -c "SELECT installed_rank, version, description, type, checksum, installed_by, execution_time, success FROM flyway_schema_history ORDER BY installed_rank;"

psql:
> docker compose exec postgres psql -U admin -d $(ENV)_db

reset:
> docker compose run --rm flyway -configFiles=/flyway/conf/dev.conf clean
> docker compose run --rm flyway -configFiles=/flyway/conf/dev.conf migrate

# make stage STAGE=B1  (copy a prepared scenario into sql/)
stage:
> test -d demo/$(STAGE) || { echo "Unknown stage '$(STAGE)'. Available: B1 B2 C1 C2 D E1 E3 F"; exit 1; }
> cp demo/$(STAGE)/* sql/

legacy:
> docker compose exec -T postgres psql -U admin -d dev_db < demo/legacy_schema.sql

demo-reset:
> git clean -fdq -- sql
> git checkout -- sql
> docker compose down -v
> docker compose up -d --wait postgres dashboard
> $(MAKE) migrate-all

down:
> docker compose down -v
