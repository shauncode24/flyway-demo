# Flyway + PostgreSQL: Automated Schema Versioning and Migration

Demonstrates automated database schema migrations with Flyway on PostgreSQL:
creating, applying, tracking and correcting versioned SQL migrations, with a CI pipeline
and a read-only dashboard.

## What is in the repository
| Path | Purpose |
|---|---|
| `docker-compose.yml` | PostgreSQL 16 (dev_db, test_db, prod_db), Flyway 10, dashboard |
| `init/` | Creates the three databases on first start |
| `conf/` | One Flyway config per environment (only dev allows `clean`) |
| `sql/` | 8 versioned migrations, 1 repeatable view, 1 `afterMigrate` callback |
| `run.ps1` / `Makefile` | Command wrappers (PowerShell is the tested one; Make has the core commands only) |
| `dashboard/` | Read-only web dashboard at http://localhost:3000 |
| `demo/` | Prepared files for the correction scenarios |
| `.github/workflows/flyway.yml` | CI: migrate a fresh database, validate, show history |
| `DEMO.md` | Step-by-step live demo runbook |

## Quick start
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\run.ps1 up
.\run.ps1 migrate-all
.\run.ps1 info
```
Open http://localhost:3000 for the dashboard.

## Correction scenarios
A checksum mismatch, B roll-forward fix, C failed migration, D repeatable migration,
E version conflict and out-of-order, F baselining. See `DEMO.md`.

## Credentials
The passwords in `docker-compose.yml`, `conf/*.conf` and the CI workflow are **demo values** for a local
throwaway database. Real projects must never commit credentials: supply them through environment
variables, a secrets manager, or GitHub Actions secrets (`${{ secrets.DB_PASSWORD }}`).

Dev, test and prod share one PostgreSQL server here for simplicity; in real life they are separate servers.
Ports 5432 (Postgres) and 3000 (dashboard) must be free on the host.

Flyway Community has no undo migrations, so mistakes are fixed by rolling forward with a new migration.
