# Flyway CI/CD Pipeline: Automated Schema Versioning and Migration

Demonstrates automated database schema migrations with Flyway on PostgreSQL, driven by a GitHub Actions
CI/CD pipeline. A developer commits a versioned SQL migration and pushes; the pipeline validates it on an
empty database, then deploys it to dev, then test, then prod (three schemas in a Supabase cloud database),
and decides success or failure. A manual workflow covers repair, baseline, out-of-order and reset.

Everything about the project (architecture, commands, scenarios, demo script, report material) is in
[PROJECT.md](PROJECT.md). [DEMO.md](DEMO.md) is the short live-demo runbook.

## What is in the repository
| Path | Purpose |
|---|---|
| `sql/` | 8 versioned migrations, 1 repeatable view, 1 `afterMigrate` callback. **This folder is what gets deployed.** |
| `.github/workflows/flyway.yml` | Main pipeline: gate on an empty database, then dev, test, prod (stops at the first failure) |
| `.github/workflows/_deploy.yml` | Reusable job that deploys to one environment (`info`, `validate`, `migrate`, `info`) |
| `.github/workflows/manual.yml` | Manual operations: `info`, `migrate`, `migrate-out-of-order`, `repair`, `baseline`, `load-legacy-schema`, `reset-schema` |
| `demo/` | Prepared files for the correction scenarios (copied into `sql/` by `run.ps1 stage`) |
| `run.ps1` | Helper: `stage`, `scenario`, `doctor`; also the commands for the optional local sandbox |
| `dashboard/` | Read-only web dashboard (local mode or Supabase schema mode) |
| `docker-compose.yml`, `init/`, `conf/`, `Makefile` | Optional local Docker sandbox for rehearsing scenarios |
| `PROJECT.md`, `DEMO.md`, `docs/REPORT.md` | Full specification, live-demo runbook, written report |

## How it works
```
git push to main
  -> migrate-from-scratch   (throwaway Postgres 16: migrate, validate, info)
  -> dev  -> test  -> prod  (Supabase schemas; each: info, validate, migrate, info)
```
A pull request runs only the first job, so nothing is deployed. Each environment is a GitHub Environment
with its own `DB_URL`, `DB_USER` and `DB_PASSWORD` secrets, and `prod` can require a reviewer's approval.

## Quick start
1. Create a Supabase project with the schemas `dev`, `test` and `prod`.
2. In GitHub, create the Environments `dev`, `test`, `prod` and add the three secrets to each
   (use the Supabase **Session pooler** connection, see PROJECT.md section 2.3).
3. Push to `main` and watch the Actions tab.

Run a scenario: stage a file, commit, push, read the run graph.
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\run.ps1 scenario C        # prints the steps for Scenario C
.\run.ps1 stage C1
git add sql; git commit -m "Add loyalty points"; git push
```

## Correction scenarios
A checksum mismatch, B roll-forward fix, C failed migration, D repeatable migration,
E version conflict and out-of-order, F baselining. See `DEMO.md` and PROJECT.md section 6.

## Credentials
Cloud credentials live only in GitHub Environment secrets and are never committed. The `admin` / `admin123`
values in `docker-compose.yml`, `conf/*.conf` and the pipeline's throwaway gate database are demo values
for local and disposable databases only. Keep any local `.env` or `*.env` secrets file out of git.

Dev, test and prod are three schemas in one Supabase database for simplicity; in real life they would be
separate databases or servers. Flyway Community has no undo migrations, so mistakes are fixed by rolling
forward with a new migration. Applied migrations are permanent: to rerun the demo, reset the schemas with
the manual workflow and restore `sql/` from the `demo-baseline` tag (PROJECT.md section 8.5).

## Optional local sandbox
The Docker stack (`.\run.ps1 up`, `migrate-all`, `demo-reset`, ...) runs the same migrations against a local
Postgres with `dev_db`, `test_db` and `prod_db`, for rehearsing without touching the cloud. Ports 5432 and
3000 must be free. See PROJECT.md section 4.5.
