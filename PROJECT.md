# Flyway CI/CD Pipeline Project: Single Source of Truth

**Automated Database Schema Versioning and Migration with Flyway, PostgreSQL (Supabase) and a GitHub Actions CI/CD Pipeline**
Course area: DevOps. Tool: Flyway Community (10.22.0). Databases: PostgreSQL 17 on Supabase (cloud: dev, test and prod as three schemas), PostgreSQL 16 (CI gate and optional local sandbox). Pipeline: GitHub Actions. Runtime for the optional local sandbox: Docker Compose. Shell: PowerShell on Windows (a Makefile is kept for Mac/Linux).

This file is the one place that describes the whole project: what it is, how the pipeline is built, what every trigger and command does, how to run the live demo from a completely fresh start, what output to expect, and the material needed for the written report. The README, the demo runbook, the report and the presentation can all be produced from it.

**The key change from the earlier version of this project:** migrations are no longer run by hand against a local database. A developer commits a migration file and pushes. The pipeline validates it on a throwaway database, then deploys it to dev, then test, then prod in a cloud database. The pipeline's success or failure decides what happens. A small manual workflow exists for the operations a pipeline should never run on its own (repair, out-of-order, baseline, reset).

Status markers used below:

- **verified (local)**: run on this repository's local Docker stack (Flyway 10.22.0, PostgreSQL 16.15, Docker Desktop on Windows 11); the output shown is real.
- **verified (pipeline)**: observed on GitHub Actions and Supabase.
- **not yet verified**: written and committed but not yet observed running. Section 12 lists each one.

---

## Contents

1. [What the project is](#1-what-the-project-is)
2. [How it is built](#2-how-it-is-built)
3. [The database schema](#3-the-database-schema)
4. [Command reference](#4-command-reference)
5. [The dashboard](#5-the-dashboard)
6. [The six correction scenarios](#6-the-six-correction-scenarios)
7. [CI/CD pipeline](#7-cicd-pipeline)
8. [Fresh live demo: step-by-step script](#8-fresh-live-demo-step-by-step-script)
9. [Report material](#9-report-material)
10. [Screenshot checklist](#10-screenshot-checklist)
11. [Troubleshooting and risks](#11-troubleshooting-and-risks)
12. [Status, open items and glossary](#12-status-open-items-and-glossary)

---

# 1. What the project is

## 1.1 One-sentence summary

Write each database change as a numbered SQL file, commit it, and let a CI/CD pipeline validate it, apply it with Flyway to dev, test and prod in order, record what ran in a history table, and decide success or failure, while mistakes are caught and fixed without damaging history.

## 1.2 The problem

When schema changes are made by hand:

1. **Environments drift apart.** Dev has a column that prod lacks, and nobody notices until a release fails.
2. **Changes get lost or applied twice.** A script is forgotten, or run a second time.
3. **Nobody can say which version a database is on.**
4. **Deployment depends on a person.** Whoever types the commands decides what reaches prod, and a laptop-only run proves nothing to anyone else.

Application code solved these problems long ago with version control, code review and automated pipelines. Database structure usually has not. This project applies the same discipline to the schema, including the last step: the pipeline, not a person at a terminal, performs the deployment.

## 1.3 What the project demonstrates

| Verb | What it means here |
|---|---|
| **Create** | Schema changes written as versioned migration files (`V1__...sql`, `V2__...sql`, ...). |
| **Apply** | Flyway runs the files in order, against three environments (dev, test, prod) with identical results. The pipeline does this, not a person. |
| **Track** | A permanent, queryable history table in each environment records what was applied, when, by whom, with a checksum, and whether it succeeded. |
| **Correct** | Six kinds of mistake are caused on purpose and recovered from without damaging history. |
| **Automate** | A pipeline gates every change on an empty database, then deploys dev, then test, then prod, stopping at the first failure. |
| **Observe** | The Actions run graph shows what happened per environment; a read-only dashboard can show the state of every environment. |

## 1.4 What Flyway is

Flyway is a database migration tool. It reads a folder of SQL files named `V<version>__<description>.sql`, compares them with a table stored inside the database (`flyway_schema_history`), and applies only the files that have not yet been applied, in version order.

Core ideas:

- **Versioned migration** (`V1__create_customers.sql`): runs exactly once, in version order. Never edited after it has been applied.
- **Repeatable migration** (`R__order_summary_view.sql`): re-runs whenever its content changes. Suited to views and similar definitions.
- **Callback** (`afterMigrate.sql`): a script that runs automatically at a defined point. Here it runs after every successful `migrate`.
- **Checksum**: when a file is applied, Flyway stores a hash of its content. If the file is later edited, `validate` and `migrate` refuse to continue.
- **Baseline**: a way to put an existing database that was never under Flyway under version control, at a chosen version.
- **Out-of-order**: a switch that lets Flyway apply a migration whose version is lower than one already applied.

File naming rule: capital `V`, version, **two underscores**, description, `.sql`. One underscore or a lowercase `v` makes Flyway ignore or reject the file.

## 1.5 Manual scripts versus Flyway

| Concern | Manual scripts | Flyway |
|---|---|---|
| Traceability | A person remembers what ran | `flyway_schema_history` records version, checksum, user, time, duration, success |
| Repeatability | Depends on who runs what, in which order | The same files give the same result on any empty database |
| Consistency | Environments drift | Dev, test and prod receive identical files |
| Error detection | Edited or missing scripts go unnoticed | Checksum validation blocks changed history |
| Automation | Hard to put in a pipeline | One command, usable in CI |
| Collaboration | Two people pick the same script number silently | Duplicate or out-of-order versions are detected |

## 1.6 Why a pipeline instead of running commands by hand

Running `migrate` at a terminal proves the migration works on one person's machine and relies on that person to run it in the right order against the right environments. The pipeline replaces that with rules that run every time:

| Concern | Commands run by hand | Pipeline |
|---|---|---|
| Who deploys | Whoever has the terminal and the credentials | The pipeline, using credentials stored as GitHub secrets |
| Bad change reaches an environment | Possible: nothing forces a pre-check | Not possible: the change must apply to an empty database first |
| Order of environments | Remembered | Enforced (dev, then test, then prod, stopping at the first failure) |
| Evidence | Terminal scrollback | A permanent, shareable Actions log per run |
| Approval | None | Optional required reviewer before an environment |

A pipeline cannot undo an applied migration (Flyway Community has no undo), so the safety comes from catching the failure **before** it reaches a real environment (the gate) and from stopping the rollout at the first failing environment.

## 1.7 Scope

**Included:** Flyway Community, PostgreSQL on Supabase (cloud), GitHub Actions (CI gate, three-stage deployment, manual operations workflow), GitHub Environments with secrets, an order-management schema, six correction scenarios, a read-only dashboard, and an optional local Docker stack kept for rehearsal.

**Not included:** a business application on top of the database; paid Flyway features (undo migrations, dry runs, advanced drift detection); other databases or migration tools; Kubernetes or infrastructure-as-code; any UI that changes data or runs migrations.

**Acknowledged simplifications:** dev, test and prod are three schemas inside one Supabase database (in real life they would be separate databases or servers); the same database user is used for all three; Supabase's shared pooler is used (see 2.1). Credentials are held as GitHub Environment secrets and never committed.

---

# 2. How it is built

## 2.1 Architecture

| Component | Role |
|---|---|
| **Git repository (GitHub)** | Holds the migration files in `sql/` and the workflows in `.github/workflows/`. A push or pull request starts the pipeline. |
| **`flyway.yml` (main pipeline)** | Gate job, then `dev`, `test`, `prod` deployment jobs. See section 7. |
| **`_deploy.yml` (reusable job)** | Runs Flyway `info`, `validate`, `migrate`, `info` against one environment. Called three times by the main pipeline. |
| **`manual.yml` (manual operations)** | Buttons in the Actions tab for `info`, `migrate`, `migrate-out-of-order`, `repair`, `baseline`, `load-legacy-schema`, `reset-schema`. |
| **GitHub Environments `dev`, `test`, `prod`** | Each holds its own secrets `DB_URL`, `DB_USER`, `DB_PASSWORD`. `prod` can require a reviewer's approval. |
| **Supabase PostgreSQL 17** | One database (`postgres`) with three schemas: `dev`, `test`, `prod`. Each schema holds its own tables and its own `flyway_schema_history`. Reached through Supabase's **Session pooler** on port 5432 (the direct connection is IPv6-only, and GitHub-hosted runners are IPv4). |
| **Throwaway PostgreSQL 16 (CI service container)** | An empty database created for each run of the gate job and discarded afterwards. |
| **Flyway 10 (Docker image)** | Runs inside the pipeline with `docker run`, with `sql/` mounted. |
| **Dashboard (Node.js)** | Read-only web page showing the history tables. Supports the cloud layout through environment variables (section 5). |
| **Local Docker sandbox (optional)** | The original Docker Compose stack (postgres, flyway, dashboard) driven by `run.ps1`. Kept for rehearsing scenarios without touching the cloud. |

Data flow of one change:

```
developer: edit/add file in sql/  ->  git commit  ->  git push to main
GitHub Actions:
  gate:  empty Postgres 16  ->  migrate, validate, info          (red = stop here, nothing real touched)
  dev:   Supabase schema "dev"  ->  info, validate, migrate, info     (red = stop; test and prod skipped)
  test:  Supabase schema "test" ->  same four steps
  prod:  Supabase schema "prod" ->  same four steps (optional approval first)
Flyway inside each step:
  read history table -> validate (checksums, duplicates, ordering)
  -> apply pending files in version order, each in its own transaction
  -> insert a row in flyway_schema_history -> run afterMigrate callback
```

PostgreSQL supports transactional DDL, so a migration that fails part-way is rolled back completely. This matters for Scenario C.

## 2.2 Repository structure

| Path | Purpose |
|---|---|
| `.github/workflows/flyway.yml` | Main pipeline: gate, then dev, test, prod |
| `.github/workflows/_deploy.yml` | Reusable deployment job for one environment |
| `.github/workflows/manual.yml` | Manual operations workflow |
| `sql/` | All migrations: V1 to V8, the repeatable view, the `afterMigrate` callback. **This folder is what gets deployed.** |
| `demo/` | Prepared scenario files that `stage` copies into `sql/` (see 2.5) |
| `run.ps1` | PowerShell helper: `stage`, `scenario`, `doctor` for the pipeline demo, plus the full local-sandbox commands |
| `docker-compose.yml`, `init/`, `conf/` | The optional local sandbox (Postgres with `dev_db`, `test_db`, `prod_db`; Flyway configs) |
| `dashboard/` | `server.js`, `public/index.html`, `Dockerfile`, `package.json` |
| `Makefile` | Same local commands for Mac/Linux (not run on this Windows machine) |
| `DEMO.md`, `README.md`, `docs/REPORT.md`, `docs/windows-powershell-commands.md` | Short runbook, overview, written report and PowerShell reference, all derived from this file |
| `.env.example` | Template for the dashboard's cloud settings (copy to the git-ignored `.env`) |
| `PROJECT.md` | This file |

## 2.3 Configuration and secrets

**In the pipeline.** Flyway is configured on the command line by `_deploy.yml` and `manual.yml`:

```
-url=<DB_URL>  -user=<DB_USER>  -password=<DB_PASSWORD>
-locations=filesystem:/flyway/sql
-schemas=<dev|test|prod>
-validateMigrationNaming=true
```

- `-schemas=<environment>` makes Flyway work inside that schema and store `flyway_schema_history` in it. This is how three environments share one cloud database.
- `validateMigrationNaming=true` makes Flyway reject badly named files instead of silently ignoring them.
- `clean` is disabled by Flyway 10 by default. Only the manual `reset-schema` action enables it (`-cleanDisabled=false`), and only after a typed confirmation.

**Secrets.** Each GitHub Environment (`dev`, `test`, `prod`) holds three secrets with the same names:

| Secret | Value |
|---|---|
| `DB_URL` | `jdbc:postgresql://aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require` (identical in all three environments) |
| `DB_USER` | `postgres.<project-ref>` (the Session pooler user form) |
| `DB_PASSWORD` | The database password |

The values are never committed. They can be created in the web UI (Settings, Environments) or from a local, git-ignored env file with the GitHub CLI: `gh secret set -f dev.env --env dev`. The Docker-only demo credentials (`admin` / `admin123`) remain in `conf/*.conf` and the CI gate service for the local and throwaway databases only.

**Why the Session pooler.** Supabase's direct connection host (`db.<ref>.supabase.co`) is IPv6-only, and GitHub-hosted runners are IPv4. The Session pooler (host `aws-0-<region>.pooler.supabase.com`, port 5432, user `postgres.<ref>`) accepts IPv4 on the free plan. Port 6543 (transaction mode) is not used because it can break Flyway.

## 2.4 Health check (local sandbox)

`docker-compose.yml` defines the Postgres health check as `pg_isready -h localhost -U admin -d postgres`. The `-h localhost` forces a TCP connection, because during first start the image runs a temporary server that listens only on the unix socket while the init script runs. `up` and `demo-reset` use `docker compose up --wait`. The cloud pipeline does not use this; the gate's service container has its own `pg_isready` health check.

## 2.5 Prepared scenario files (`demo/`)

`stage <name>` copies the files from `demo/<name>/` into `sql/`. In the pipeline demo, a scenario step is always the same three actions: **stage, commit, push**.

| Stage | File(s) copied | Content | Used in |
|---|---|---|---|
| B1 | `V9__add_phone.sql` | `ALTER TABLE customers ADD COLUMN phon VARCHAR(15);` (typo, valid SQL) | B |
| B2 | `V10__fix_phone_column.sql` | `ALTER TABLE customers RENAME COLUMN phon TO phone;` | B |
| C1 | `V11__add_loyalty_points.sql` | `ALTER TABL customers ...` (syntax error) | C |
| C2 | `V11__add_loyalty_points.sql` | `ALTER TABLE customers ADD COLUMN loyalty_points INT NOT NULL DEFAULT 0;` (corrected, overwrites C1) | C |
| D | `R__order_summary_view.sql` | The view with an extra `SUM(oi.quantity) AS item_count` column (overwrites the original) | D |
| E1 | `V12__add_discount_code.sql`, `V12__add_loyalty_tier.sql` | Two different files, both version 12 | E |
| E3 | `V12_5__add_audit_note.sql` | `ALTER TABLE orders ADD COLUMN audit_note VARCHAR(200);` (version 12.5) | E |
| F | `V9__add_customer_phone.sql` | `ALTER TABLE customers ADD COLUMN phone VARCHAR(15);` | F |
| (none) | `legacy_schema.sql` | A hand-built schema with no Flyway history; loaded into a schema by the manual `load-legacy-schema` action | F |

---

# 3. The database schema

An **order-management system**. It grows through eight versions so the migrations show different kinds of change. The schema is identical in every environment; in the cloud each environment's tables live in its own schema (`dev.customers`, `test.customers`, `prod.customers`).

## 3.1 Final structure

- **customers**: id, name, email (required, unique), created_at
- **products**: id, name, price (not negative), stock
- **orders**: id, customer_id (foreign key), status (NEW, PAID, SHIPPED or CANCELLED), created_at
- **order_items**: id, order_id (foreign key, cascades on delete), product_id (foreign key), quantity (greater than zero), unit_price
- **order_summary** (view): per order, the customer, status and total

## 3.2 The migrations

| Version | File | What it does | Concept shown |
|---|---|---|---|
| V1 | `V1__create_customers.sql` | Creates `customers` (id, name, created_at) | Basic table creation |
| V2 | `V2__create_products.sql` | Creates `products`, price must be >= 0 | Constraints |
| V3 | `V3__create_orders_and_items.sql` | Creates `orders` and `order_items` with foreign keys, cascade on delete, quantity > 0 | Foreign keys |
| V4 | `V4__add_customer_email.sql` | Adds an optional `email` column | Evolving an existing table |
| V5 | `V5__backfill_email_and_enforce.sql` | Backfills `email` from the name, then makes it `NOT NULL` and `UNIQUE` | Data migration: add nullable, backfill, enforce |
| V6 | `V6__add_indexes.sql` | Indexes on `orders.customer_id`, `order_items.order_id`, `order_items.product_id` | Performance migration |
| V7 | `V7__seed_data.sql` | 3 customers, 3 products, 3 orders, 4 order items | Seed data |
| V8 | `V8__add_order_status_check.sql` | Check constraint limiting `orders.status` to NEW, PAID, SHIPPED, CANCELLED | Rule on existing data |
| R | `R__order_summary_view.sql` | `CREATE OR REPLACE VIEW order_summary` | Repeatable migration |
| afterMigrate | `afterMigrate.sql` | `ANALYZE;` refreshes planner statistics | Callback, runs after every migrate |

**Expected result.** With the seed data, `SELECT * FROM <schema>.order_summary` totals are: order 1 = 6097.00 (1499.00 + 2 x 2299.00), order 2 = 4999.00, order 3 = 2299.00.

**Known limitation.** V5's backfill is a no-op on a fresh database, because `customers` is empty when it runs (the seed data arrives in V7). The pattern (add nullable, backfill, enforce) is still correct and is what the file demonstrates, but the demo does not show rows being rewritten. Editing V1 to V3 to seed rows would change checksums of already-applied files and could clash with V7's emails, so this was left as is.

## 3.3 Expected history after a full migrate (verified, local)

| rank | version | description | checksum |
|---|---|---|---|
| 1 | 1 | create customers | -603799595 |
| 2 | 2 | create products | 981205911 |
| 3 | 3 | create orders and items | -502065848 |
| 4 | 4 | add customer email | -919276812 |
| 5 | 5 | backfill email and enforce | 9991856 |
| 6 | 6 | add indexes | -1263317754 |
| 7 | 7 | seed data | -1277905681 |
| 8 | 8 | add order status check | -140223157 |
| 9 | (none) | order summary view | 306726401 |

The checksums depend only on file content, so they are the same on every machine, in every schema and in all three environments. Flyway ignores line-ending differences when computing checksums. In the cloud, `installed_by` is the pooler user (`postgres`), not `admin`. Compare the cloud history against this table with the query in 4.4.

---

# 4. Command reference

There are four ways to act on the system:

1. **Push to git** (the normal way): starts the pipeline.
2. **Manual workflow** in the GitHub Actions tab: the operations the pipeline does not run.
3. **Local helper commands** (`run.ps1 stage`, `scenario`, `doctor`): prepare files and print cheat cards.
4. **Inspection**: Actions logs, and SQL against Supabase.

Run local commands from the project folder in PowerShell. Once per terminal window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

PowerShell blocks scripts by default. `-Scope Process` applies only to the current window and disappears when it is closed.

## 4.1 Starting the pipeline

| Trigger | What runs |
|---|---|
| `git push` to `main` | Gate, then dev, test, prod |
| Pull request (any branch) | Gate only. Nothing is deployed. |
| Push to any other branch | Nothing |
| Actions tab, "Flyway migrations", Run workflow (on `main`) | Gate, then dev, test, prod (a manual re-run, for example after a repair) |
| Failed run, "Re-run failed jobs" | Retries only the failed environment onward |

Deployment jobs run only when the run is on `main`; a pull request or any other branch can never reach the cloud database.

## 4.2 Manual workflow actions

Actions tab, **Manual Flyway operations**, Run workflow. Inputs: `environment` (dev, test, prod), `action`, `baseline_version` (default 8), `confirm`.

| Action | What it does | Under the hood | Guard rails |
|---|---|---|---|
| `info` | Lists every migration and its state, read-only | `flyway info` | none |
| `migrate` | Applies pending migrations, then shows `info` | `flyway migrate` | none |
| `migrate-out-of-order` | Same, allowing a lower version that arrived late | `flyway -outOfOrder=true migrate` | none |
| `repair` | Realigns stored checksums with the files, removes failed entries | `flyway repair` | `confirm` must equal the environment name |
| `baseline` | Marks an existing schema as being at `baseline_version` | `flyway -baselineVersion=<n> -baselineDescription="Legacy database" baseline` | none |
| `load-legacy-schema` | Builds the hand-made, non-Flyway tables in the chosen schema | `psql` runs `demo/legacy_schema.sql` after `SET search_path` | **blocked on prod** |
| `reset-schema` | Drops everything in the schema so it can be rebuilt | `flyway -cleanDisabled=false clean` | `confirm` must equal the environment name |

The workflow uses the `sql/` folder of the branch it is run on. Each action runs under the chosen GitHub Environment, so `prod` approval rules also apply to manual runs.

## 4.3 Local helper commands

`.\run.ps1 <command> [argument]`. These work without Docker running unless noted.

| Command | What it does |
|---|---|
| `stage <name>` | Copies a prepared scenario file set from `demo/<name>/` into `sql/`. Valid names: `B1 B2 C1 C2 D E1 E3 F`. Unknown names are rejected. Does not commit or push. |
| `scenario <A-F>` | Prints a cheat card of the commands for that scenario. Runs nothing. |
| `doctor` | Pre-demo checklist. Also checks the local ports and the git tree. Exits 1 on a hard failure. |

Git commands used throughout the demo:

| Command | Purpose |
|---|---|
| `git add sql; git commit -m "..."; git push` | Send a staged scenario to the pipeline |
| `git revert HEAD --no-edit; git push` | Undo the last pushed change by adding a new commit (never rewrite pushed history) |
| `git tag demo-baseline` | Mark the commit where `sql/` holds V1 to V8 only (done once, see 8.1) |

## 4.4 Inspection

**Actions logs.** Each run's job log contains Flyway's `info` table before and after `migrate`. This replaces the terminal output of the earlier version.

**Supabase SQL Editor** (read-only queries):

```sql
-- the history table of one environment
select installed_rank, version, description, type, checksum, installed_by, execution_time, success
from dev.flyway_schema_history order by installed_rank;

-- are two environments identical? (returns no rows when they are)
(select version, description, checksum from dev.flyway_schema_history
 except select version, description, checksum from test.flyway_schema_history)
union all
(select version, description, checksum from test.flyway_schema_history
 except select version, description, checksum from dev.flyway_schema_history);

-- columns of customers in dev
select column_name from information_schema.columns
where table_schema = 'dev' and table_name = 'customers' order by ordinal_position;
```

**Supabase Table Editor.** Switch the schema dropdown between `dev`, `test` and `prod`.

## 4.5 Local sandbox commands (optional)

The Docker stack lets you rehearse every scenario with immediate feedback and without commits. Syntax: `.\run.ps1 <command> [argument] [-Target dev|test|prod] [-Force]`. The default target is `dev`. Every command first checks that Docker is running.

| Command | What it does |
|---|---|
| `up` / `down` | Start Postgres and the dashboard and wait until healthy / stop everything and **wipe all data** |
| `info`, `validate`, `migrate`, `repair`, `baseline`, `migrate-ooo` | The Flyway actions against the chosen local environment (`baseline` sets version 8; `migrate-ooo` allows out-of-order) |
| `migrate-all` | `migrate` on dev, test, prod; stops at the first failure |
| `status` / `compare <env>` | `info` for all three / compare migration histories |
| `history` / `psql` | Print the history table / open an interactive session |
| `legacy` | Load `demo/legacy_schema.sql` into local `dev_db` |
| `reset` | Dev only: `clean` then `migrate` |
| `demo-reset` | Clean, fully migrated local state (refuses if `sql/` has uncommitted edits to tracked files unless `-Force`) |

**Mac/Linux:** `make <command> ENV=dev|test|prod`: `up`, `info`, `validate`, `migrate`, `migrate-ooo`, `repair`, `baseline`, `migrate-all`, `history`, `psql`, `reset`, `legacy`, `demo-reset`, `down`, and `make stage STAGE=B1`. Not run on this Windows machine.

---

# 5. The dashboard

A read-only page at **http://localhost:3000** that refreshes every 3 seconds. It never runs a migration, edits a file or writes to a database. All changes are made through git and the pipeline; the dashboard is a window into the system.

## 5.1 What it shows

**Header.** Project title, a live indicator ("Updated hh:mm:ss"), and a "Changed hh:mm:ss ·" note that appears whenever any status, version, checksum or history count changes. If the server cannot be reached the page says "Dashboard server unreachable" rather than showing stale data.

**Banner.** One line: all environments in sync, or which ones need attention.

**Environment cards** (dev, test, prod): current schema version; applied, pending and failed counts; how many migrations differ from the reference environment (dev); a status badge.

| Status | Meaning |
|---|---|
| In sync | Everything applied, nothing differs |
| Pending | Migration files exist that have not been applied |
| Drifted | Applied migrations differ from the reference environment |
| Failed | A migration is recorded as failed |
| Not initialised | The environment exists but has no migration history yet |
| Unreachable | The database cannot be contacted |

**Migration matrix.** One row per migration file, one column per environment. Cells read Applied, Pending, Failed, Baselined, or nothing. Tags: **differs** (this environment's stored checksum does not match the reference environment's, which is how a changed repeatable migration or an edited applied file becomes visible) and **out of order** (applied after a higher version).

**Schema history.** A tab per environment showing the live `flyway_schema_history` table.

## 5.2 Presentation mode

Press **P** on the page, or open `http://localhost:3000/?present`. Text is enlarged for a projector. Light and dark themes follow the operating system.

## 5.3 Connecting to the cloud database

The dashboard has two modes, chosen by environment variables:

| Mode | Variables | Reads |
|---|---|---|
| **Local** (default) | `PGHOST`, `PGUSER`, `PGPASSWORD` | `dev_db`, `test_db`, `prod_db`, table `public.flyway_schema_history` |
| **Cloud schemas** | `PG_SCHEMAS=true`, `PGDATABASE=postgres`, `PGHOST=aws-0-<region>.pooler.supabase.com`, `PGPORT=5432`, `PGUSER=postgres.<project-ref>`, `PGPASSWORD`, `PGSSL=true` | Schemas `dev`, `test`, `prod` in one database, table `<schema>.flyway_schema_history` |

The variables belong in a git-ignored `.env` file (copy `.env.example`) that Docker Compose reads; `docker-compose.yml` passes them to the dashboard with local defaults, so without a `.env` the dashboard stays in local mode. **Status: the cloud mode is implemented in `dashboard/server.js` and wired in `docker-compose.yml` (`docker compose config` is valid), but it has not yet been checked against Supabase (section 12).** The dashboard also reads the `sql/` folder (mounted read-only) to list files that exist but are not applied, so it should be run from a working copy at the commit being deployed.

## 5.4 Behaviour in special situations

- **Not migrated yet:** shows Not initialised, and all its migrations show Pending.
- **A migration that fails and rolls back cleanly (Scenario C)** leaves no failed row in the history, so it appears as **Pending**. In the pipeline version the failure is stopped at the gate and never reaches any environment.
- **Baselined database:** migrations at or below the baseline version show as **Baselined**, not Pending, and the environment counts as In sync.
- **Safety:** every piece of text from the database is escaped before display, never interpreted as markup.

## 5.5 What it deliberately does not do

No buttons to migrate, repair, baseline or reset; no editing or uploading of migration files; no login; no history beyond what Flyway records.

## 5.6 Technical notes

`GET /api/state` returns JSON with `generatedAt`, `reference`, `rows` (one per migration, with a `cells` object per environment) and `envs` (one per environment: `status`, `current`, `applied`, `pending`, `failed`, `drift`, `history`). The server queries each environment's `flyway_schema_history` and reads `sql/`.

---

# 6. The six correction scenarios

Each scenario: the problem, the pipeline flow, the fix, the lesson. In each, "push" means `git add sql; git commit; git push` to `main`, and the result is read from the **Actions run graph** (jobs `migrate-from-scratch`, `dev`, `test`, `prod`).

**Starting state for every scenario:** `sql/` holds V1 to V8 plus the view and callback; dev, test and prod are all at version 8 (nine applied entries). Section 8.5 describes how to return to this state between runs.

**About the output shown.** The Flyway output below is real, **captured on the local stack (verified, local)**. In the pipeline the same messages appear in the job logs, with the schema name reading `"dev"`, `"test"` or `"prod"` instead of `"public"`. The red/green run graphs for each scenario are **not yet verified** in the pipeline; only the first deployment (all green) has been observed.

**Two behaviours differ from the local version because a pipeline deploys everything:**

- A migration pushed to `main` reaches dev, test and prod in one run. The "dev is ahead of test and prod" state only appears if a reviewer gate pauses the run (section 7.4).
- A broken migration is stopped by the gate, so it never reaches a real environment. The "rolled back, still Pending in dev" state of the local version is replaced by "stopped before dev".

## Scenario A: checksum mismatch (applied history is protected)

**Problem.** Someone edits a migration that has already been applied.

**Pipeline flow**
```powershell
Add-Content sql\V2__create_products.sql "-- harmless comment"
git add sql; git commit -m "Edit applied V2"; git push
```
- `migrate-from-scratch`: **green** (an empty database has no stored checksum to disagree with).
- `dev`: **red** at *Validate*. `test` and `prod` are skipped.

**Real output of the failing validation** (exit code 1):
```
ERROR: Validate failed: Migrations have failed validation
Migration checksum mismatch for migration version 2
-> Applied to database : 981205911
-> Resolved locally    : 1302983372
Either revert the changes to the migration, or run repair to update the schema history.
```

**Fix (revert).** `git revert HEAD --no-edit; git push` (green again).

**Fix (deliberate, harmless edit).** Keep the edit, then run the manual **repair** action on `dev` (`confirm` = `dev`) and re-run the failed run. `test` now fails the same way, so repair `test`, re-run, repair `prod`, re-run. Check the new checksum with the history query in 4.4.

**Lesson.** Applied history cannot be silently rewritten, and the pipeline enforces this on every environment, not just the developer's.

**What if a real change is needed?** Do not edit the applied file. Add a new migration (for example `V9__alter_products.sql`) and push it; the pipeline applies it to every environment. Editing an applied script is wrong for three reasons: the databases already ran the old text, so the file would no longer describe what is actually in them; a new database built from the edited files would differ from the existing ones; and Flyway would never re-run the edited file anyway. `repair` is only for a harmless edit (a comment or formatting) that does not change what the SQL does, because it just updates the stored checksum and runs nothing.

## Scenario B: wrong migration that succeeded (roll forward)

**Problem.** A migration with a typo (`phon` instead of `phone`) is valid SQL, so it applies. Nothing fails; the mistake is simply in the database.

**Pipeline flow**
```powershell
.\run.ps1 stage B1                 # V9 adds column "phon"
git add sql; git commit -m "Add phone"; git push      # all four jobs green: V9 reaches dev, test, prod
.\run.ps1 stage B2                 # V10 renames phon to phone
git add sql; git commit -m "Fix phone column"; git push   # green
```
Check in Supabase (query 4.3's `information_schema` form): after the first push the column is `phon`; after the second it is `phone`.

**Fix.** Add a new migration. Never edit V9.

**Lesson.** History is append-only. Flyway Community has no undo, so you roll forward. The pipeline cannot catch a mistake that is valid SQL; review and tests do.

## Scenario C: failed migration (the gate catches it, PostgreSQL rolls back)

**Problem.** A migration contains a syntax error (`ALTER TABL`).

**Pipeline flow**
```powershell
.\run.ps1 stage C1                 # V11 with a syntax error
git add sql; git commit -m "Add loyalty points"; git push
```
- `migrate-from-scratch`: **red** in the migrate step. `dev`, `test`, `prod` are **skipped**: the broken file never touches a real environment.
```powershell
.\run.ps1 stage C2                 # overwrites V11 with the corrected file
git add sql; git commit -m "Fix V11"; git push
```
- All four jobs **green**. Overwriting V11 is safe because it was never applied anywhere.

**Real output of the failing migrate** (verified, local):
```
Migrating schema "public" to version "11 - add loyalty points"
ERROR: Migration of schema "public" to version "11 - add loyalty points" failed! Changes successfully rolled back.
ERROR: Script V11__add_loyalty_points.sql failed
SQL State  : 42601
Message    : ERROR: syntax error at or near "TABL"
Location   : /flyway/sql/V11__add_loyalty_points.sql
Line       : 1
```

**Fix.** Correct the file and push again.

**Lesson.** PostgreSQL supports transactional DDL, so a failure leaves no half-applied state, and the pipeline's gate stops a bad file before any real environment sees it. To see the run fail without it being on `main`, push the broken file to a branch and open a pull request: the gate runs, goes red, and nothing is deployed.

## Scenario D: repeatable migration changes

**Problem.** The view definition changes (a new `item_count` column).

**Pipeline flow**
```powershell
.\run.ps1 stage D                  # overwrites the view file
git add sql; git commit -m "Add item_count to view"; git push
```
All four jobs green. In each environment only the repeatable migration re-runs (the log's `info` shows the old view row as **Superseded** and the new one as **Success**).

**Real output** (verified, local):
```
Migrating schema "public" with repeatable migration "order summary view"
Successfully applied 1 migration to schema "public"
```

To show test and prod **drifting** (the "differs" tag on the dashboard, or a non-empty result from the compare query in 4.4), set Required reviewers on `test` or `prod` (section 7.4): the run pauses after `dev`, and the environments differ until you approve.

**Fix.** Approve the paused run (or, without a gate, there is nothing to fix: the pipeline already caught every environment up).

**Lesson.** Repeatable migrations track content, not version numbers.

## Scenario E: version conflict and out-of-order

**Problem.** Two people each add a V12 file. Later, a lower-numbered file (V12.5) arrives after a higher one (V13) has been applied.

**Pipeline flow**
```powershell
.\run.ps1 stage E1                 # two files both numbered V12
git add sql; git commit -m "Two V12 files"; git push
```
- Gate: **red** ("Found more than one migration with version 12"). Nothing deployed.
```powershell
Rename-Item sql\V12__add_loyalty_tier.sql V13__add_loyalty_tier.sql
git add sql; git commit -m "Renumber to V13"; git push
```
- All four jobs **green**: V12 and V13 reach all environments.
```powershell
.\run.ps1 stage E3                 # V12.5
git add sql; git commit -m "Add V12.5"; git push
```
- Gate: **green** (on an empty database V12.5 simply applies between V12 and V13).
- `dev`: **red** at *Validate*, because V12.5 is older than the applied V13. `test` and `prod` are skipped.

Then run the manual **migrate-out-of-order** action on `dev`, then on `test`, then on `prod` (each would fail validation the same way). Check with `info`, and re-run the main pipeline to confirm it is green again.

**Real output** (verified, local):
```
ERROR: Found more than one migration with version 12
Offenders:
-> /flyway/sql/V12__add_loyalty_tier.sql (SQL)
-> /flyway/sql/V12__add_discount_code.sql (SQL)
```
After the rename, V12 and V13 apply ("now at version v13"). Then with V12.5 added:
```
ERROR: Validate failed: Migrations have failed validation
Detected resolved migration not applied to database: 12.5.
To ignore this migration, set -ignoreMigrationPatterns='*:ignored'. To allow executing this migration, set -outOfOrder=true.
```
`migrate-out-of-order`:
```
WARNING: outOfOrder mode is active. Migration of schema "public" may not be reproducible.
Migrating schema "public" to version "12.5 - add audit note" [out of order]
```
`info` lists V12.5 with state **Out of Order**.

**Fix.** Renumber the duplicate. Apply the late arrival with out-of-order enabled, per environment, deliberately.

**Lesson.** Team collaboration creates numbering conflicts. The pipeline's validate step ignores only *pending* migrations (section 7.3), so a skipped-over version is still caught. Out-of-order is a deliberate exception, and Flyway warns the result may not be reproducible.

## Scenario F: baselining an existing database

**Problem.** A database exists that was built by hand and never put under Flyway.

**Preparation.** Return everything to the starting state (8.5), so `sql/` holds V1 to V8 only.

**Steps** (all on `dev`; nothing is pushed until the last step)
1. Manual **reset-schema** on `dev` (`confirm` = `dev`). The schema is now empty.
2. Manual **load-legacy-schema** on `dev`. Check in Supabase: tables exist in `dev`, with no `flyway_schema_history`.
3. Manual **migrate** on `dev`: **red** (non-empty schema without history).
4. Manual **baseline** on `dev`, version `8`.
5. Manual **info** on `dev`: V1 to V7 **Below Baseline**, V8 **Ignored (Baseline)**, a **Baseline** row at version 8.
6. Stage and push:
```powershell
.\run.ps1 stage F                  # V9 adds customers.phone
git add sql; git commit -m "Add phone"; git push
```
All four jobs green: `dev` applies only V9 and the view; `test` and `prod` (already at V8 with real history) apply the same V9 and view.

**Real output** (verified, local). `migrate` is refused:
```
ERROR: Found non-empty schema(s) "public" but no schema history table. Use baseline() or set baselineOnMigrate to true to initialize the schema history table.
```
`baseline`: `Successfully baselined schema with version: 8`. After the stage-F push: `Migrating schema "public" to version "9 - add customer phone"` and the repeatable view; `Successfully applied 2 migrations ... now at version v9`. The dashboard shows V1 to V8 as **Baselined**.

**Fix.** Baseline at the version that matches the existing schema.

**Lesson.** A legacy database can be put under version control without being rebuilt. Do not push to `main` between steps 1 and 6: `dev` would be half-built and the pipeline would fail there.

---

# 7. CI/CD pipeline

## 7.1 The workflows

| File | Triggers | Purpose |
|---|---|---|
| `flyway.yml` | pull request; push to `main`; manual dispatch | Gate job, then calls `_deploy.yml` for dev, test, prod |
| `_deploy.yml` | called by `flyway.yml` | Deploys to one environment (input: `environment`) |
| `manual.yml` | manual dispatch only | The operations in 4.2 |

## 7.2 Job graph of `flyway.yml`

```
migrate-from-scratch  ->  dev  ->  test  ->  prod
 (gate, empty PG16)      (each: needs the previous job; each runs _deploy.yml)
```

1. **migrate-from-scratch (the gate).** Starts a throwaway PostgreSQL 16 service (database `ci_db`, user `admin`) with a health check, checks out the repository, and runs Flyway `migrate`, `validate` and `info` against the empty database. Runs for every trigger, including pull requests.
2. **dev, test, prod.** Run only when the run is on `main` (`if: github.ref == 'refs/heads/main'`), each needing the previous job to succeed. Each calls `_deploy.yml` with its environment name and `secrets: inherit`.
3. **Stop at the first failure.** If dev fails, test and prod are skipped. If the gate fails, nothing is deployed.

## 7.3 Steps of `_deploy.yml`

The job runs under the GitHub Environment of the same name (`environment: ${{ inputs.environment }}`), which supplies `DB_URL`, `DB_USER`, `DB_PASSWORD` and any approval rule. Then:

| Step | Command | Fails when |
|---|---|---|
| Before | `flyway info` | The database cannot be reached or credentials are wrong |
| Validate | `flyway -ignoreMigrationPatterns=*:pending validate` | An applied migration was edited (checksum), or an older version was skipped over |
| Migrate | `flyway migrate` | A migration has a SQL error (Postgres rolls it back) |
| After | `flyway info` | (shows the final state in the log) |

All commands use `-schemas=<environment>`. The validate step ignores *pending* migrations only. A plain `validate` treats every not-yet-applied migration as an error, which would fail the very first deployment to an empty environment (this was observed, see 11).

## 7.4 Optional approval gate

In GitHub, Settings, Environments, `prod` (or `test`), enable **Required reviewers**. The run then pauses before that environment and waits for **Review deployments**. This also produces the intermediate state in which dev is ahead of prod, which Scenario D and the dashboard use.

## 7.5 What the outcome means

- **Gate green, all environments green:** the change works from scratch and was applied everywhere, identically.
- **Gate red:** the change is broken on an empty database. It is blocked before any real environment sees it.
- **Gate green, `dev` red at Validate:** an applied file was edited or a version was skipped (Scenarios A and E).
- **Gate green, `dev` green, `test` or `prod` red:** that environment is out of step with dev. Investigate that environment; later environments are skipped.

## 7.6 Manual operations are separate on purpose

`repair`, `migrate-out-of-order`, `baseline` and `reset-schema` change history or discard data. They are never part of the automatic path. They run only from the manual workflow, under the Environment's approval rules, and the destructive ones require the environment name typed as confirmation.

## 7.7 Status

**Verified (pipeline).** The first full run, after the validate-step fix, was green through the gate, dev, test and prod, and Supabase showed the migrated tables and history in all three schemas.
**Not yet verified.** The `manual.yml` actions; the red and green behaviour of each scenario (section 6) in the pipeline; the prod approval gate; the `github.ref` condition added after that first run.

---

# 8. Fresh live demo: step-by-step script

Goal: demonstrate everything **from nothing**: empty cloud schemas, no migrations applied, no scenario files staged. The audience's actions are *stage, commit, push, watch the Actions tab*. Total time about 30 minutes (about 4 for Part 1, 2 to 3 each for A to F, 3 for wrap-up).

## 8.1 Preparation (not part of the demo)

Do these well before presenting.

1. **Cloud database.** A Supabase project with the schemas `dev`, `test`, `prod` (run `create schema dev; create schema test; create schema prod;`). The schemas must be empty and there must be no stray tables in `public`.
2. **GitHub Environments.** `dev`, `test`, `prod`, each with secrets `DB_URL`, `DB_USER`, `DB_PASSWORD` (section 2.3). Optionally Required reviewers on `prod` (and, for the drift demo, `test`).
3. **Baseline commit.** The repository is pushed to GitHub with `main` containing `sql/` with V1 to V8, the view and the callback only. After one green run: `git tag demo-baseline` on that commit, and `git push origin demo-baseline`.
4. **Local tools.** PowerShell open in the project folder with `Set-ExecutionPolicy -Scope Process Bypass`. Browser tabs: the repo's Actions tab, the Supabase Table Editor and SQL Editor, and (if wired, see 5.3) the dashboard.
5. **No uncommitted changes** in `sql/` (`git status` clean).
6. **Rehearse the whole sequence once**, including a reset (8.5). Rehearsing locally first with the Docker sandbox (4.5) is fast; the cloud rehearsal is still required.

## 8.2 Starting position (what the audience sees)

Empty `dev`, `test` and `prod` schemas in Supabase (nothing in the Table Editor). The Actions tab shows previous runs, or none. `sql/` in the editor shows V1 to V8.

```powershell
.\run.ps1 doctor
```

*Say:* "Before anything, a checklist." `doctor` confirms the git tree is clean and the demo files exist.

## 8.3 Part 1: Create, apply, track (about 4 min)

*Concept:* a database is built from versioned files; a pipeline applies them to every environment; Flyway tracks what has run.

**Step 1.1: show what is pending.** Actions, "Manual Flyway operations", Run workflow: environment `dev`, action `info`. *Expected:* the log shows nine entries (V1 to V8 and the repeatable view), all **Pending**, `Schema version: << Empty Schema >>`. *Say:* "These nine files exist in `sql/`; Flyway sees none applied." *Screenshot.*

**Step 1.2: let the pipeline apply everything.** Actions, "Flyway migrations", Run workflow on `main` (or push an empty commit: `git commit --allow-empty -m "Deploy baseline"; git push`). *Expected:* `migrate-from-scratch` green, then `dev`, `test`, `prod` turn green one after another. Open the `dev` job: the **After** step's `info` shows all nine **Success**:
```
Creating Schema History table "dev"."flyway_schema_history" ...
Migrating schema "dev" to version "1 - create customers"
...
Migrating schema "dev" to version "8 - add order status check"
Migrating schema "dev" with repeatable migration "order summary view"
Successfully applied 9 migrations to schema "dev", now at version v8
Executing SQL callback: afterMigrate
```
*Say:* "Nobody ran a migrate command. One push, and the pipeline built all three environments in order." *Screenshots:* the run graph; a job log.

**Step 1.3: inspect the result.** Supabase Table Editor, switch the schema among `dev`, `test`, `prod`: each holds the same tables and its own `flyway_schema_history`. SQL Editor: run the history query (4.4). *Say:* "Every change is recorded permanently with a checksum of the file. That checksum is what protects history, as we will see in Scenario A." *Screenshots:* tables per schema; the history table.

**Step 1.4: prove they are identical.** Run the compare query from 4.4. *Expected:* no rows. *Say:* "Same files, three schemas, identical outcome. This is what removes environment drift."

## 8.4 Scenarios A to F

Run them in order. Each starts with `.\run.ps1 scenario <letter>` if you want the cheat card; section 6 has the full flow and the output. In every scenario, after a push, switch to the Actions tab and open the newest run.

**Scenario A (about 3 min): someone edits an applied file**
```powershell
Add-Content sql\V2__create_products.sql "-- harmless comment"
git add sql; git commit -m "Edit applied V2"; git push
```
*Expect:* gate green, `dev` red at Validate, `test` and `prod` skipped. *Say:* "We changed a file that is already applied, even just a comment. The gate is happy, because an empty database has nothing to disagree with. The real environment is not. Flyway compares checksums and refuses." *Point at:* the two checksums in the log. Fix: `git revert HEAD --no-edit; git push` (green). Optionally show the repair path (section 6, Scenario A). *Screenshots:* the red run, the fix.

**Scenario B (about 3 min): a wrong migration that succeeded**
```powershell
.\run.ps1 stage B1
git add sql; git commit -m "Add phone"; git push
.\run.ps1 stage B2
git add sql; git commit -m "Fix phone column"; git push
```
*Say:* "V9 has a typo, `phon`. It is valid SQL, so the pipeline is green and the typo is now in all three environments. We do not edit V9. We add V10, which renames the column. History only grows. The free edition has no undo, so we roll forward." *Show:* Supabase `information_schema` query: `phon`, then `phone`.

**Scenario C (about 3 min): a migration with an error**
```powershell
.\run.ps1 stage C1
git add sql; git commit -m "Add loyalty points"; git push
.\run.ps1 stage C2
git add sql; git commit -m "Fix V11"; git push
```
*Say:* "A syntax error. The gate runs it on an empty database and reports it; Flyway says the changes were rolled back because PostgreSQL treats schema changes as transactions. `dev`, `test` and `prod` were never touched, they were skipped. We fix the file and push again." *Show:* red then green run; the error in the gate log. *Screenshots:* the error and the skipped jobs.

**Scenario D (about 3 min): a repeatable migration changes**
```powershell
.\run.ps1 stage D
git add sql; git commit -m "Add item_count to view"; git push
```
*Say:* "The view definition changed. Only that repeatable migration re-ran, because Flyway tracks its content, not a version number." With a reviewer on `test`/`prod`, approve after pausing and show the compare query (non-empty) before and (empty) after.

**Scenario E (about 4 min): version conflict and out-of-order**
```powershell
.\run.ps1 stage E1
git add sql; git commit -m "Two V12 files"; git push
Rename-Item sql\V12__add_loyalty_tier.sql V13__add_loyalty_tier.sql
git add sql; git commit -m "Renumber to V13"; git push
.\run.ps1 stage E3
git add sql; git commit -m "Add V12.5"; git push
```
Then the manual **migrate-out-of-order** on `dev`, `test`, `prod`, and a re-run of the main pipeline.
*Say:* "Two developers both used V12. Flyway refuses to guess, so the gate stops it. We renumber one. Then a V12.5 arrives after V13 is applied; `dev` fails validation. With out-of-order enabled, deliberately and per environment, it can be applied, and Flyway warns that this may not be reproducible."

**Scenario F (about 4 min): adopting a legacy database**
Return to baseline first (8.5), then in the manual workflow on `dev`: `reset-schema` (`confirm` = `dev`), `load-legacy-schema`, `migrate` (red), `baseline` (version 8), `info`. Then:
```powershell
.\run.ps1 stage F
git add sql; git commit -m "Add phone"; git push
```
*Say:* "First we create a schema someone built by hand, with real data and no Flyway history. Flyway refuses to touch a non-empty schema it does not know. We baseline it at version 8, which says 'everything up to here already exists'. Only newer migrations run after that." *Show:* the `info` output with Below Baseline and Baseline rows; Supabase `dev` tables.

## 8.5 Resetting between runs (replaces `demo-reset`)

Applied migrations stay applied, and git history stays. To start again:

1. Manual **reset-schema** on `dev`, `test`, `prod` (`confirm` = each name).
2. Restore `sql/` to the baseline and push, which makes the pipeline rebuild all three:
```powershell
git clean -fd sql
git rm -rq sql
git checkout demo-baseline -- sql
git commit -m "Reset demo to baseline"
git push
```
(If the commit reports nothing to commit, `sql/` already matched.)

## 8.6 Wrap-up (about 3 min)

Reset (8.5), show all three schemas rebuilt and identical, then switch back to the summary:

- Create: versioned files. Apply: the pipeline deploys the same files to three environments, in order. Track: history table with checksums, in each environment. Correct: six scenarios, never rewriting history. Automate: the gate proves it from scratch on every push, and the first failure stops the rollout.
- Limits: Community edition rolls forward instead of undoing; one shared cloud database with three schemas; a pipeline cannot catch a mistake that is valid SQL.

## 8.7 Cheat sheet: demo order at a glance

```
Part 1:   manual info (dev), run main pipeline, Supabase tables + history, compare query
A:        edit V2, push (dev red) | revert, push (green)
B:        stage B1, push, stage B2, push
C:        stage C1, push (gate red) | stage C2, push (green)
D:        stage D, push
E:        stage E1, push (gate red) | rename V12->V13, push | stage E3, push (dev red) | manual migrate-out-of-order x3
F:        reset (8.5), manual: reset-schema, load-legacy-schema, migrate (red), baseline, info | stage F, push
Reset:    manual reset-schema x3, restore sql/ from demo-baseline, push
```

---

# 9. Report material

Written so each section can be pasted into the report. Chapter numbers follow the required outline. Replace each `[Screenshot: ...]` with an image from section 10.

## 9.1 Introduction

Application code is versioned, reviewed, tested and deployed automatically. Database structure often is not. When schema changes are applied by hand, environments drift apart (dev has a column that prod lacks), changes are lost or applied twice, and nobody can say which version a database is on. This project shows the alternative: every schema change is a numbered SQL file, committed to version control, validated and applied by a CI/CD pipeline in a fixed order, recorded permanently, and correctable without damaging history. It covers four actions (create, apply, track, correct) and two DevOps layers on top: automation through a pipeline that decides success or failure, and observation through run logs and a read-only dashboard.

## 9.2 What Flyway is

(Use section 1.4. Add: Flyway applies the same DevOps principles to the database that version control and pipelines apply to code: the schema lives in version control, is built by a pipeline, and is identical in every environment.)

## 9.3 Manual SQL scripts versus Flyway

(Use the tables in sections 1.5 and 1.6.)

## 9.4 Architecture

(Use sections 2.1 and 2.2. Include a diagram: developer, GitHub repository, GitHub Actions (gate job with a throwaway Postgres 16, then dev, test, prod jobs), Supabase PostgreSQL with schemas dev, test, prod; GitHub Environments holding the secrets; the manual workflow as a side branch.) `[Screenshot: Actions run graph]`

## 9.5 Migration lifecycle

```
write file -> commit and push -> gate (empty DB) -> per environment: validate (checksums, duplicates, ordering)
  -> apply in a transaction -> record in flyway_schema_history -> afterMigrate callback
```

Each migration runs in its own transaction. PostgreSQL supports transactional DDL, so a failure rolls the whole migration back and leaves nothing half-applied (Scenario C). On success, one row is written with the version, a checksum of the file, the user, the time, the duration and the success flag.

## 9.6 Implementation: the schema

(Use section 3: the final structure, the migration table, the expected totals for the view, and the V5 limitation noted honestly.) The design principles are: one logical change per file; add nullable, backfill, then enforce (V4 and V5); seed data as its own migration (V7); constraints added after data exists (V8); a view as a repeatable migration; a callback for housekeeping.

## 9.7 Tracking

The Actions log shows `info` before and after each deployment: nine entries Pending, then nine Success. The history table in each schema (query in 4.4) has these columns:

| Column | Meaning |
|---|---|
| `installed_rank` | Order in which entries were applied |
| `version` | Version number (empty for repeatable migrations) |
| `description` | Taken from the file name |
| `type` | SQL, BASELINE, etc. |
| `script` | The file name |
| `checksum` | Hash of the file content when applied; the basis of tamper detection |
| `installed_by` | Database user that ran it |
| `installed_on` | Timestamp |
| `execution_time` | Milliseconds taken |
| `success` | Whether it completed |

Across environments, the compare query proves identical histories, and the dashboard (section 5) makes drift, pending work and failures visible at a glance. `[Screenshots: info before, info after, history table, three schemas in Supabase]`

## 9.8 Correction scenarios

(Use section 6 in full, A to F, including the pipeline flow, the real error output and the lesson for each.) `[Screenshots: failure and fix for each scenario]`

## 9.9 Automation: the CI/CD pipeline

(Use section 7.) State clearly what the pipeline protects against: a migration that works on a developer's laptop but fails on an empty database (the gate), a syntax error, a duplicate version, an edited applied file, a skipped-over version, and a bad change reaching prod because dev already failed (stop at the first failure). State what it does not protect against: a migration that is valid SQL but wrong (Scenario B). Describe the manual workflow as the deliberate exception for repair, baseline, out-of-order and reset. `[Screenshots: red run, green run, approval gate]`

## 9.10 Best practices

- Never edit an applied migration; add a new one.
- One logical change per file.
- Backfill before enforcing (add nullable, fill, then tighten).
- Roll forward instead of undoing.
- Keep secrets out of the repository (GitHub Environment secrets); use separate secrets per environment.
- Keep `clean` disabled by default; require a typed confirmation to enable it.
- Validate on an empty database on every push, before any real environment.
- Deploy in order and stop at the first failure.
- Deploy only from `main`; use pull requests to run the gate without deploying.
- Require approval before prod.
- Detect drift by comparing environments.
- Treat out-of-order as a deliberate, documented exception.

## 9.11 Limitations

- Flyway Community has no undo migrations, dry runs or advanced drift detection. These are paid features, so recovery here is by rolling forward.
- Dev, test and prod are three schemas in one Supabase database for simplicity, and they share a database user. In real life they would be separate databases with separate credentials.
- The pipeline cannot judge whether a valid migration is correct; it can only prove that it applies.
- Scenario recovery is slower than at a terminal: every step is a commit and a pipeline run.
- Applied migrations cannot be un-applied; between demo runs the schemas must be reset with the manual workflow and `sql/` restored from git.
- The dashboard is read-only and records no history beyond what Flyway stores. A cleanly rolled-back failure leaves no row, so it appears as Pending.
- The "out of order" and "Baselined" labels on the dashboard are derived from the history table, not from Flyway's own `info` logic.

## 9.12 Conclusion

Schema changes were written as versioned files, validated on an empty database, applied by a pipeline to three environments in order, tracked in a permanent history table, and corrected safely in six different failure situations. The pipeline, not a person at a terminal, decides success or failure, and it stops the rollout at the first failing environment. A short manual workflow covers the operations that must never run automatically, and the demonstration can be reset and repeated.

---

# 10. Screenshot checklist

Save in `docs/screenshots/`, named as below.

| # | File | Capture | When |
|---|---|---|---|
| 1 | `01-info-pending.png` | Manual `info` log with all nine Pending | Step 1.1 |
| 2 | `02-run-graph-green.png` | Actions run graph, all four jobs green | Step 1.2 |
| 3 | `03-info-success.png` | The After `info` in the `dev` job, all Success | Step 1.2 |
| 4 | `04-supabase-schemas.png` | Table Editor showing `dev`, `test`, `prod` with the same tables | Step 1.3 |
| 5 | `05-history.png` | The history query result | Step 1.3 |
| 6 | `06-compare-identical.png` | Compare query returning no rows | Step 1.4 |
| 7 | `07-A-fail.png`, `07-A-fix.png` | Red `dev` job with the checksum mismatch; green after the revert | Scenario A |
| 8 | `08-B-green.png`, `08-B-columns.png` | Green run; `phon` then `phone` in `information_schema` | Scenario B |
| 9 | `09-C-gate-red.png`, `09-C-skipped.png` | Gate log with the rolled-back error; `dev`/`test`/`prod` skipped | Scenario C |
| 10 | `10-D-drift.png` | Paused run and a non-empty compare result (or dashboard "differs") | Scenario D |
| 11 | `11-E-duplicate.png`, `11-E-validate.png`, `11-E-ooo.png` | Duplicate version; V12.5 validation error; Out of Order | Scenario E |
| 12 | `12-F-refused.png`, `12-F-baselined.png` | Non-empty refusal; `info` with Baseline rows | Scenario F |
| 13 | `13-approval-gate.png` | Run waiting on "Review deployments" for prod | Section 7.4 |
| 14 | `14-secrets.png` | Environment secrets list (names only, no values) | Section 2.3 |

---

# 11. Troubleshooting and risks

| Symptom | Cause and fix |
|---|---|
| `dev` job: "Schema history table ... does not exist yet" then "Detected resolved migration not applied" | A plain `validate` on an empty environment. Already handled: the pipeline uses `-ignoreMigrationPatterns=*:pending` (7.3). This was the first real failure of this pipeline. |
| Connection refused or timeout | The direct connection host (`db.<ref>.supabase.co`) is IPv6-only. Use the Session pooler host in `DB_URL`. |
| Authentication failed | The pooler user must be `postgres.<project-ref>`, not just `postgres`. Check `DB_PASSWORD`. |
| Secret is empty / "invalid URL" | Secrets were added as repository secrets instead of to the specific Environment, or an Environment name is misspelled. Names must be exactly `dev`, `test`, `prod`. |
| Flyway fails on pooler port 6543 | Transaction mode. Use port 5432 (session mode). |
| `dev` green, `test` or `prod` red on the same change | That environment is out of step (Scenarios A and E need a per-environment manual action). |
| After a manual `repair` or `migrate-out-of-order` the next push still fails on `test` or `prod` | The manual action was run on one environment only. Run it on each, then re-run the failed run. |
| Pipeline stops at `dev` after a half-finished Scenario F | `dev` is in the legacy state without history. Finish the baseline, or reset (8.5), before pushing. |
| Manual workflow does not appear in the Actions tab | `manual.yml` must be on the default branch (`main`). |
| Pull request shows only the gate | Intended: deployment jobs run only on `main`. |
| Annotations "Node.js 20 is deprecated" or "ubuntu-latest will migrate" | Harmless warnings from `actions/checkout` and the runner image. |
| `reset-schema` refused | `confirm` must equal the environment name exactly. |
| Flyway ignores or rejects a file | Check the name: capital `V`, **two** underscores. |
| `run.ps1` cannot be loaded (execution policy) | `Set-ExecutionPolicy -Scope Process Bypass` in each new PowerShell window. |
| Local sandbox: "Docker is not running" / port 5432 or 3000 in use | Start Docker Desktop / stop the program using the port. |
| A scenario's output differs from this file | Flyway wording can change between versions. This file was verified on 10.22.0. |
| "A more recent version of Flyway is available" | Harmless banner printed on every command. |
| Commit/line-ending warnings from git | `LF will be replaced by CRLF` is harmless. Flyway's checksum ignores line endings. |

Risks to manage before presenting:

- **Applied migrations are permanent.** A mistaken push cannot be undone in the cloud, only rolled forward or reset with the manual workflow. Rehearse the reset (8.5).
- **Network and GitHub availability.** Every step depends on GitHub and Supabase being reachable. Keep screenshots of a good run as a fallback, and push the next scenario while still explaining the previous one, because runs take a minute or so.
- **Stray files in `sql/`.** Anything committed there is deployed. Check `git status` before each commit.
- **Free-tier limits.** A paused or rate-limited Supabase project fails every run at the first `info` step. Open the project the day before.
- **Secrets hygiene.** Secrets are never committed; env files used to load them (`*.env`) must stay git-ignored.

---

# 12. Status, open items and glossary

## 12.1 What is verified

**Local sandbox (verified, local).** On Flyway 10.22.0 / PostgreSQL 16.15, in order: fresh start, `info`, `migrate`, `migrate-all`, `history`, `compare`, `doctor`, `scenario`, `demo-reset`, and scenarios A to F with the outputs shown in section 6. The dashboard was checked through its API for Not initialised, In sync, Drifted, Baselined and Out-of-order states.

**Pipeline (verified, pipeline).** On GitHub Actions and Supabase (PostgreSQL 17.11): connection through the Session pooler with Environment secrets; the first run failed in `dev` at Validate (fixed, see 11); the second run was green through the gate, `dev`, `test` and `prod`; the migrated tables and history were present in all three schemas.

## 12.2 Open items

1. **Manual workflow** (`manual.yml`) has not been run. Try `info`, then the others. The risky ones are `reset-schema` (Flyway `clean` against Supabase schemas) and `load-legacy-schema` (`psql` through the pooler).
2. **Scenarios A to F through the pipeline** have not been run; only the first all-green deployment has. Rehearse each, including the reset in 8.5.
3. **`demo-baseline` tag** has to be created on the commit whose `sql/` holds V1 to V8 only.
4. **Approval gate** on `prod` (and optionally `test`) has not been set up or observed.
5. **Dashboard cloud mode** is implemented (`PG_SCHEMAS`, `PGSSL`) and wired in `docker-compose.yml` with a `.env.example`, but it has not been checked against Supabase. Create `.env` from the example, run `.\run.ps1 up`, and look at `http://localhost:3000`.
6. **Secrets files.** `.gitignore` now excludes `.env` and `*.env` (but keeps `.env.example`); still keep the actual secret values out of any committed file.
7. **Screenshots** have not been taken.
8. **V5 backfill** is a no-op on a fresh database (see 3.2). Decide whether to leave it and state it, or seed rows earlier (changes checksums of applied files).
9. **Makefile** was updated to match `run.ps1` but not executed (no `make` on this Windows machine).
10. **Other documents.** `README.md`, `DEMO.md`, `docs/REPORT.md`, `docs/windows-powershell-commands.md` and the `run.ps1 scenario` cheat cards now follow the cloud pipeline flow. They are derived from this file and have not been rehearsed; if a step is wrong, fix it here and in the matching document.
11. **Final report and slides** are produced from section 9 of this file.

## 12.3 Glossary

| Term | Meaning |
|---|---|
| Migration | A SQL file that changes the schema |
| Versioned migration | `V<n>__name.sql`; runs once, in order |
| Repeatable migration | `R__name.sql`; re-runs when its content changes |
| Callback | A script Flyway runs at a defined point, such as `afterMigrate.sql` |
| History table | `flyway_schema_history`; Flyway's record of what has run, one per schema here |
| Checksum | A hash of a file's content, stored when the file is applied |
| Validate | Compare applied migrations with files on disk |
| Repair | Update stored checksums and remove failed entries |
| Baseline | Declare an existing database to be at a given version |
| Out-of-order | Apply a migration with a lower version than the current one |
| Drift | Two environments whose applied migrations differ |
| Roll forward | Fix a mistake with a new migration rather than undoing |
| Clean | Drop everything in a schema or database; here only via the manual `reset-schema` action |
| Transactional DDL | Schema changes that roll back on failure (PostgreSQL) |
| CI / CD | Continuous integration (prove every change) / continuous deployment (apply it automatically) |
| Gate | The first pipeline job: applies all migrations to an empty database before any real environment is touched |
| GitHub Environment | A named deployment target in GitHub (`dev`, `test`, `prod`) with its own secrets and optional approval rule |
| Reusable workflow | A workflow that other workflows call (`_deploy.yml`) |
| Session pooler | Supabase's IPv4-reachable connection endpoint (port 5432), used because the direct host is IPv6-only |
| Schema (PostgreSQL) | A namespace inside one database; used here to separate dev, test and prod |
