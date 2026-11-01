# Flyway Schema Versioning Project: Single Source of Truth

**Automated Database Schema Versioning and Migration with Flyway and PostgreSQL**
Course area: DevOps. Tool: Flyway Community (tested on 10.22.0). Database: PostgreSQL 16. Runtime: Docker Compose. CI: GitHub Actions. Shell: PowerShell on Windows (a Makefile is kept for Mac/Linux).

This file is the one place that describes the whole project: what it is, how it is built, what every command does, how to run the live demo from a completely fresh start, what output to expect, and the material needed for the written report. The README, the demo runbook, the report and the presentation can all be produced from it.

Everything marked **verified** was run on this repository (Flyway 10.22.0, PostgreSQL 16.15, Docker Desktop on Windows 11), and the output shown is real.

---

## Contents

1. [What the project is](#1-what-the-project-is)
2. [How it is built](#2-how-it-is-built)
3. [The database schema](#3-the-database-schema)
4. [Command reference](#4-command-reference)
5. [The dashboard](#5-the-dashboard)
6. [The six correction scenarios](#6-the-six-correction-scenarios)
7. [CI pipeline](#7-ci-pipeline)
8. [Fresh live demo: step-by-step script](#8-fresh-live-demo-step-by-step-script)
9. [Report material](#9-report-material)
10. [Screenshot checklist](#10-screenshot-checklist)
11. [Troubleshooting and risks](#11-troubleshooting-and-risks)
12. [Status, open items and glossary](#12-status-open-items-and-glossary)

---

# 1. What the project is

## 1.1 One-sentence summary

Write each database change as a numbered SQL file, let Flyway apply the files in order to any database, record what ran in a history table, and prove that mistakes are caught and fixed safely.

## 1.2 The problem

When schema changes are made by hand:

1. **Environments drift apart.** Dev has a column that prod lacks, and nobody notices until a release fails.
2. **Changes get lost or applied twice.** A script is forgotten, or run a second time.
3. **Nobody can say which version a database is on.**

Application code solved these problems long ago with version control, code review and automated pipelines. Database structure usually has not. This project applies the same discipline to the schema.

## 1.3 What the project demonstrates

| Verb | What it means here |
|---|---|
| **Create** | Schema changes written as versioned migration files (`V1__...sql`, `V2__...sql`, ...). |
| **Apply** | Flyway runs the files automatically, in order, against PostgreSQL, and against three environments (dev, test, prod) with identical results. |
| **Track** | A permanent, queryable history table records what was applied, when, by whom, with a checksum, and whether it succeeded. |
| **Correct** | Six kinds of mistake are caused on purpose and recovered from without damaging history. |
| **Automate** | A CI pipeline builds an empty database and applies every migration on each push. |
| **Observe** | A live, read-only dashboard shows the state of every environment. |

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

## 1.6 Scope

**Included:** Flyway Community, PostgreSQL 16, Docker Compose, GitHub Actions, a read-only dashboard, an order-management schema, six correction scenarios.

**Not included:** a business application on top of the database; paid Flyway features (undo migrations, dry runs, advanced drift detection); other databases or migration tools; cloud hosting, Kubernetes, infrastructure-as-code; any UI that changes data or runs migrations.

**Acknowledged simplifications:** dev, test and prod share one PostgreSQL server (in real life they would be separate servers); credentials are demo values (real projects use secrets or environment variables).

---

# 2. How it is built

## 2.1 Architecture

Three containers, managed by Docker Compose, plus a separate CI pipeline.

| Service | Role |
|---|---|
| **postgres** | PostgreSQL 16 hosting `dev_db`, `test_db` and `prod_db`. The databases are created on first start by an init script. Port 5432. A health check makes the other services wait until initialisation has finished. |
| **flyway** | Flyway 10, started on demand per command (not a long-running service) with a chosen environment config. Mounts the `sql/` and `conf/` folders. Declared with the `tools` profile, so `up` does not start it. |
| **dashboard** | A small Node.js web server on port 3000. Reads `flyway_schema_history` from each database and the migration files on disk (mounted read-only) and serves a live page. It never writes to any database. |
| **CI (GitHub Actions)** | Outside Docker Compose. Starts a throwaway PostgreSQL service and runs Flyway against it on each push. |

All three databases live on one Postgres server. That is a deliberate simplification.

Data flow of one migration:

```
file in sql/  ->  Flyway reads history table  ->  validate (checksums, duplicates, ordering)
              ->  apply pending files in version order, each in its own transaction
              ->  insert a row in flyway_schema_history (version, checksum, user, time, success)
              ->  run afterMigrate callback
```

PostgreSQL supports transactional DDL, so a migration that fails part-way is rolled back completely. This matters for Scenario C.

## 2.2 Repository structure

| Path | Purpose |
|---|---|
| `docker-compose.yml` | The three services and the data volume `pgdata` |
| `init/01-create-databases.sql` | Creates `dev_db`, `test_db`, `prod_db` on first start |
| `conf/dev.conf`, `test.conf`, `prod.conf` | One Flyway config per environment |
| `sql/` | All migrations: V1 to V8, the repeatable view, the `afterMigrate` callback |
| `demo/` | Prepared scenario files that `stage` copies into `sql/` (see 2.5) |
| `run.ps1` | PowerShell command wrapper; every action is one short command |
| `Makefile` | Same commands for Mac/Linux (not run on this Windows machine) |
| `dashboard/` | `server.js`, `public/index.html`, `Dockerfile`, `package.json` |
| `.github/workflows/flyway.yml` | CI pipeline |
| `DEMO.md`, `README.md` | Earlier runbook and overview; this file supersedes them |
| `docs/REPORT.md` | Earlier report draft; section 9 of this file supersedes it |
| `PROJECT.md` | This file |

## 2.3 Configuration

Each environment has one config file under `conf/`:

```
flyway.url=jdbc:postgresql://postgres:5432/<env>_db
flyway.user=admin
flyway.password=admin123
flyway.locations=filesystem:/flyway/sql
flyway.validateMigrationNaming=true
flyway.cleanDisabled=false        # dev.conf ONLY
```

- `validateMigrationNaming=true` makes Flyway reject badly named files instead of silently ignoring them.
- Only `dev.conf` sets `cleanDisabled=false`. Flyway 10 disables `clean` (which drops everything) by default as a safety feature, so test and prod can never be wiped by accident.
- **Credentials** (`admin` / `admin123`) are demo values for a local throwaway database. Real projects must never commit credentials: they come from environment variables, a secrets manager or GitHub Actions secrets (`${{ secrets.DB_PASSWORD }}`).

## 2.4 Health check

`docker-compose.yml` defines the Postgres health check as `pg_isready -h localhost -U admin -d postgres`. The `-h localhost` forces a TCP connection. During first start the image runs a temporary server that listens only on the unix socket while the init script runs, so a socket-based check could report "healthy" before the three databases exist. The TCP check only passes once the real server is up. `up` and `demo-reset` use `docker compose up --wait`, which waits for this check.

## 2.5 Prepared scenario files (`demo/`)

`stage <name>` copies the files from `demo/<name>/` into `sql/`. Nothing else is needed during the demo.

| Stage | File(s) copied | Content | Used in |
|---|---|---|---|
| B1 | `V9__add_phone.sql` | `ALTER TABLE customers ADD COLUMN phon VARCHAR(15);` (typo, valid SQL) | B |
| B2 | `V10__fix_phone_column.sql` | `ALTER TABLE customers RENAME COLUMN phon TO phone;` | B |
| C1 | `V11__add_loyalty_points.sql` | `ALTER TABL customers ...` (syntax error) | C, CI |
| C2 | `V11__add_loyalty_points.sql` | `ALTER TABLE customers ADD COLUMN loyalty_points INT NOT NULL DEFAULT 0;` (corrected, overwrites C1) | C |
| D | `R__order_summary_view.sql` | The view with an extra `SUM(oi.quantity) AS item_count` column (overwrites the original) | D |
| E1 | `V12__add_discount_code.sql`, `V12__add_loyalty_tier.sql` | Two different files, both version 12 | E |
| E3 | `V12_5__add_audit_note.sql` | `ALTER TABLE orders ADD COLUMN audit_note VARCHAR(200);` (version 12.5) | E |
| F | `V9__add_customer_phone.sql` | `ALTER TABLE customers ADD COLUMN phone VARCHAR(15);` | F |
| (none) | `legacy_schema.sql` | A hand-built schema with no Flyway history; loaded by the `legacy` command | F |

---

# 3. The database schema

An **order-management system**. It grows through eight versions so the migrations show different kinds of change.

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

**Expected result.** With the seed data, `SELECT * FROM order_summary` totals are: order 1 = 6097.00 (1499.00 + 2 x 2299.00), order 2 = 4999.00, order 3 = 2299.00.

**Known limitation.** V5's backfill is a no-op on a fresh database, because `customers` is empty when it runs (the seed data arrives in V7). The pattern (add nullable, backfill, enforce) is still correct and is what the file demonstrates, but the demo does not show rows being rewritten. Editing V1 to V3 to seed rows would change checksums of already-pushed files and could clash with V7's emails, so this was left as is.

## 3.3 Expected history after a full migrate (verified)

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

All with `installed_by = admin`, `success = t`. The checksums depend only on file content, so they are the same on every machine and in all three environments. Flyway ignores line-ending differences when computing checksums.

---

# 4. Command reference

Run all commands from the project folder in PowerShell. Once per terminal window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

PowerShell blocks scripts by default. `-Scope Process` applies only to the current window and disappears when it is closed.

Syntax: `.\run.ps1 <command> [argument] [-Target dev|test|prod] [-Force]`. The default target is `dev`. Every command first checks that Docker is running and exits with a clear message if it is not.

## 4.1 Lifecycle

| Command | What it does | Under the hood |
|---|---|---|
| `up` | Starts Postgres and the dashboard, building the dashboard image if needed, and waits until both are healthy. The databases are created on first start. | `docker compose up -d --build --wait postgres dashboard` |
| `down` | Stops everything and **wipes all data** (the volume), so the next `up` is a brand-new server. | `docker compose down -v` |

## 4.2 Core Flyway actions

These run Flyway in a one-off container against the chosen environment (`-Target`). Each returns Flyway's exit code, so a failed validation or migration is visible as a non-zero exit.

| Command | What it does | Under the hood |
|---|---|---|
| `info` | Lists every migration file and its state: Pending, Success, Failed, Superseded, Out of Order, Below Baseline. Read-only. | `flyway info` |
| `validate` | Checks that applied migrations still match their files (checksums, versions). Fails on any difference. Read-only. | `flyway validate` |
| `migrate` | Applies all pending migrations in version order. Validates first. | `flyway migrate` |
| `repair` | Updates stored checksums to match the files on disk and removes failed entries. Used after a deliberate, harmless edit. | `flyway repair` |
| `baseline` | Marks an existing database as being at version 8 (description "Legacy database"). Only newer migrations apply afterwards. | `flyway baseline -baselineVersion=8 -baselineDescription="Legacy database"` |
| `migrate-ooo` | Same as `migrate` but with out-of-order enabled, so a lower-numbered file that arrived late can be applied. | `flyway migrate -outOfOrder=true` |

## 4.3 Multi-environment

| Command | What it does |
|---|---|
| `migrate-all` | Runs `migrate` on dev, then test, then prod. **Stops at the first failure**, so prod is never touched after a failed dev run. |
| `status` | Runs `info` for all three environments in one view. |
| `compare <env> [-Target ref]` | Compares the migration history (version, description, checksum, success) of the reference environment (default dev) with `<env>`. Prints "identical" and exits 0, or lists each entry present in only one side and exits 1. Example: `.\run.ps1 compare test`. |

## 4.4 Inspection

| Command | What it does | Under the hood |
|---|---|---|
| `history` | Prints the history table of the target: rank, version, description, type, checksum, installed_by, execution_time, success. | `psql` query on `flyway_schema_history` |
| `psql` | Opens an interactive PostgreSQL session on the target database. Useful commands: `\d customers` (describe a table), `\dt` (list tables), `\q` (quit). | `docker compose exec postgres psql -U admin -d <env>_db` |

## 4.5 Demonstration helpers

| Command | What it does |
|---|---|
| `stage <name>` | Copies a prepared scenario file set from `demo/<name>/` into `sql/`. Valid names: `B1 B2 C1 C2 D E1 E3 F`. Unknown names are rejected. |
| `scenario <A-F>` | Prints a cheat card of the commands for that scenario. Runs nothing. |
| `legacy` | Loads `demo/legacy_schema.sql` into `dev_db`: a hand-built schema with data and no Flyway history (for Scenario F). |
| `reset` | **Dev only.** Runs `clean` (drops everything in dev) then `migrate`. Test and prod cannot be cleaned. |
| `doctor` | Pre-demo checklist: ports 5432 and 3000 free (if the stack is down) or stack running, git tree clean, `DEMO.md` / `demo/` files present. Exits 1 on a hard failure; uncommitted changes are only a warning. |
| `demo-reset` | Returns the whole system to a clean, fully migrated state: removes untracked files in `sql/`, restores `sql/` from git, wipes the data volume, starts the stack, and migrates dev, test and prod. **Refuses to run if `sql/` has uncommitted edits to tracked files**, unless you add `-Force`, which discards them. |

`demo-reset` relies on git: it restores `sql/` from the last commit, so migration files must be committed.

## 4.6 Mac/Linux equivalents (Makefile, not run on this machine)

`make <command> ENV=dev|test|prod`: `up`, `info`, `validate`, `migrate`, `migrate-ooo`, `repair`, `baseline`, `migrate-all`, `history`, `psql`, `reset`, `legacy`, `demo-reset`, `down`, and `make stage STAGE=B1`. It does not have `status`, `compare`, `doctor` or `scenario`.

---

# 5. The dashboard

A read-only page at **http://localhost:3000** that refreshes every 3 seconds. It never runs a migration, edits a file or writes to a database. All changes are made from the command line; the dashboard is a window into the system.

## 5.1 What it shows

**Header.** Project title, a live indicator ("Updated hh:mm:ss"), and a "Changed hh:mm:ss ·" note that appears whenever any status, version, checksum or history count changes, so the audience notices when a command has finished. If the server cannot be reached the page says "Dashboard server unreachable" rather than showing stale data.

**Banner.** One line: all environments in sync, or which ones need attention.

**Environment cards** (dev, test, prod): current schema version; applied, pending and failed counts; how many migrations differ from the reference environment (dev); a status badge.

| Status | Meaning |
|---|---|
| In sync | Everything applied, nothing differs |
| Pending | Migration files exist that have not been applied |
| Drifted | Applied migrations differ from the reference environment |
| Failed | A migration is recorded as failed |
| Not initialised | The database exists but has no migration history yet |
| Unreachable | The database cannot be contacted |

**Migration matrix.** One row per migration file, one column per environment. Cells read Applied, Pending, Failed, Baselined, or nothing. Tags:

- **differs**: this environment's stored checksum does not match the reference environment's. This is how a changed repeatable migration, or an edited applied file, becomes visible.
- **out of order**: the migration was applied after a higher version had already been applied.

Rows are ordered by version numerically (version 10 after version 9), repeatable migrations last.

**Schema history.** A tab per environment showing the live `flyway_schema_history` table: rank, version, description, type, checksum, installed by, installed on, execution time, success. A clear message appears when an environment has no history yet.

## 5.2 Presentation mode

Press **P** on the page, or open `http://localhost:3000/?present`. Text is enlarged for a projector. Light and dark themes follow the operating system.

## 5.3 Behaviour in special situations

- **Not migrated yet:** shows Not initialised, and all its migrations show Pending.
- **A migration that fails and rolls back cleanly (Scenario C)** leaves no failed row in the history, so it appears as **Pending**. The failure itself is shown in the terminal.
- **Baselined database:** migrations at or below the baseline version show as **Baselined**, not Pending, and the environment counts as In sync.
- **Safety:** every piece of text from the database is escaped before display, never interpreted as markup.

## 5.4 What it deliberately does not do

No buttons to migrate, repair, baseline or reset; no editing or uploading of migration files; no login; no history beyond what Flyway records.

## 5.5 Technical notes

`GET /api/state` returns JSON with `generatedAt`, `reference` (the reference environment), `rows` (one per migration, with a `cells` object per environment: `status`, `mismatch`, `outOfOrder`, `checksum`, ...) and `envs` (one per environment: `status`, `current`, `applied`, `pending`, `failed`, `drift`, `history`). The server queries each database's `flyway_schema_history` and reads `sql/` (mounted read-only). Connection settings come from `PGHOST`, `PGUSER`, `PGPASSWORD`.

---

# 6. The six correction scenarios

Each scenario: the problem, what Flyway does, the fix, the lesson. All six were run in order on this repository and behave as written. **Output shown is real.** Lines of Flyway's "newer version available" banner are omitted.

## Scenario A: checksum mismatch (applied history is protected)

**Problem.** Someone edits a migration that has already been applied.

**Commands**
```powershell
.\run.ps1 validate                                            # passes
Add-Content sql\V2__create_products.sql "-- harmless comment"
.\run.ps1 validate                                            # FAILS
.\run.ps1 migrate                                             # refuses too
git checkout sql/V2__create_products.sql
.\run.ps1 validate                                            # passes again
```

**Real output of the failing `validate`** (exit code 1):
```
ERROR: Validate failed: Migrations have failed validation
Migration checksum mismatch for migration version 2
-> Applied to database : 981205911
-> Resolved locally    : 1302983372
Either revert the changes to the migration, or run repair to update the schema history.
```

**Fix.** Revert the file. If the edit was intentional and harmless, `.\run.ps1 repair` updates the stored checksum (then `.\run.ps1 history` shows the new value; restore the file and repair again to undo).

**Lesson.** Applied history cannot be silently rewritten.

## Scenario B: wrong migration that succeeded (roll forward)

**Problem.** A migration with a typo (`phon` instead of `phone`) is valid SQL, so it applies. Nothing fails; the mistake is simply in the database.

**Commands**
```powershell
.\run.ps1 stage B1        # V9 adds column "phon"
.\run.ps1 migrate         # succeeds
.\run.ps1 history
.\run.ps1 stage B2        # V10 renames phon to phone
.\run.ps1 migrate
.\run.ps1 psql            # then: \d customers   and   \q
```

**Real output:** V9 applies ("now at version v9"), then V10 ("now at version v10"). `\d customers` lists `email` and `phone`.

**Fix.** Add a new migration. Never edit V9.

**Lesson.** History is append-only. Flyway Community has no undo, so you roll forward.

## Scenario C: failed migration (PostgreSQL rolls back)

**Problem.** A migration contains a syntax error (`ALTER TABL`).

**Commands**
```powershell
.\run.ps1 stage C1        # V11 with a syntax error
.\run.ps1 migrate         # FAILS
.\run.ps1 info            # V11 still Pending
.\run.ps1 stage C2        # overwrites V11 with the corrected file
.\run.ps1 migrate         # succeeds
.\run.ps1 migrate-all     # bring test and prod level before Scenario D
```

**Real output of the failing `migrate`:**
```
Migrating schema "public" to version "11 - add loyalty points"
ERROR: Migration of schema "public" to version "11 - add loyalty points" failed! Changes successfully rolled back.
ERROR: Script V11__add_loyalty_points.sql failed
SQL State  : 42601
Message    : ERROR: syntax error at or near "TABL"
Location   : /flyway/sql/V11__add_loyalty_points.sql
Line       : 1
```
`info` then lists V11 as **Pending** (not Failed).

**Fix.** Correct the file and run `migrate` again. Because the failed migration never completed, it is safe to change it.

**Lesson.** PostgreSQL supports transactional DDL, so a failure leaves no half-applied state. The dashboard shows V11 as Pending too.

Important: dev is now ahead of test and prod (they never received V9 to V11 in the full run). The final `migrate-all` brings them level so Scenario D shows only its own difference.

## Scenario D: repeatable migration changes

**Problem.** The view definition changes (a new `item_count` column).

**Commands**
```powershell
.\run.ps1 stage D         # overwrites the view file
.\run.ps1 migrate         # dev only: only the repeatable migration re-runs
.\run.ps1 compare test    # lists the difference
.\run.ps1 migrate-all     # test and prod catch up
.\run.ps1 compare test    # identical again
```

**Real output.** `migrate` on dev:
```
Migrating schema "public" with repeatable migration "order summary view"
Successfully applied 1 migration to schema "public"
```
`compare test`:
```
dev and test differ:
  [only in dev] R:order summary view  order summary view  checksum=1022084846  success=true
```
`info` shows the old view row as **Superseded** and the new one as Success. The dashboard shows test and prod as **Drifted**, with "differs" on the view row, until `migrate-all`.

**Fix.** Migrate the remaining environments.

**Lesson.** Repeatable migrations track content, not version numbers.

## Scenario E: version conflict and out-of-order

**Problem.** Two people each add a V12 file. Later, a lower-numbered file (V12.5) arrives after a higher one (V13) has been applied.

**Commands**
```powershell
.\run.ps1 stage E1                                                  # two files both numbered V12
.\run.ps1 migrate                                                   # FAILS: duplicate version
Rename-Item sql\V12__add_loyalty_tier.sql V13__add_loyalty_tier.sql
.\run.ps1 migrate                                                   # applies V12 and V13
.\run.ps1 stage E3                                                  # V12.5
.\run.ps1 migrate                                                   # FAILS validation
.\run.ps1 migrate-ooo                                               # applies it out of order
.\run.ps1 info
```

**Real output.**
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
`migrate-ooo`:
```
WARNING: outOfOrder mode is active. Migration of schema "public" may not be reproducible.
Migrating schema "public" to version "12.5 - add audit note" [out of order]
```
`info` lists V12.5 with state **Out of Order**. The dashboard tags the cell "out of order".

**Fix.** Renumber the duplicate. Apply the late arrival with out-of-order enabled.

**Lesson.** Team collaboration creates numbering conflicts. Out-of-order is a deliberate exception, and Flyway warns the result may not be reproducible.

## Scenario F: baselining an existing database

**Problem.** A database exists that was built by hand and never put under Flyway.

**Commands**
```powershell
.\run.ps1 demo-reset -Force     # clean slate and removes leftover E files
.\run.ps1 down
.\run.ps1 up                    # empty server, no history anywhere
.\run.ps1 legacy                # builds the hand-made schema in dev_db
.\run.ps1 psql                  # then: \dt   and   \q   (tables exist, no flyway_schema_history)
.\run.ps1 migrate               # FAILS: non-empty schema, no history
.\run.ps1 baseline              # marks the database as version 8
.\run.ps1 info
.\run.ps1 stage F               # V9 adds customers.phone
.\run.ps1 migrate               # only V9 and the view run
```

**Real output.** `migrate` is refused:
```
ERROR: Found non-empty schema(s) "public" but no schema history table. Use baseline() or set baselineOnMigrate to true to initialize the schema history table.
```
`baseline`: `Successfully baselined schema with version: 8`. `info` shows V1 to V7 as **Below Baseline**, V8 as **Ignored (Baseline)**, and one **Baseline** row (version 8, "Legacy database"). After `stage F` and `migrate`: `Migrating schema "public" to version "9 - add customer phone"` and the repeatable view; `Successfully applied 2 migrations ... now at version v9`. The dashboard shows V1 to V8 as **Baselined**.

**Fix.** Baseline at the version that matches the existing schema.

**Lesson.** A legacy database can be put under version control without being rebuilt.

---

# 7. CI pipeline

File: `.github/workflows/flyway.yml`. Triggers: every **push** and every **pull request**.

## 7.1 What it does

1. Starts a throwaway **PostgreSQL 16** service (database `ci_db`, user `admin`) with a health check.
2. Checks out the repository.
3. Runs Flyway `migrate` against the empty database.
4. Runs `validate`.
5. Runs `info`, so the migration table appears in the job log.

Flyway runs through `docker run --network host` with the repository's `sql/` folder mounted.

## 7.2 What the outcome means

- **Green:** the migrations work from scratch on an empty database.
- **Red:** a change must be fixed before it goes any further. Example: a branch containing the Scenario C1 file fails in the migrate step with the syntax error and "Changes successfully rolled back".

## 7.3 Secrets practice

Credentials in the workflow are demo values. Real projects supply them through GitHub Actions secrets (for example `${{ secrets.DB_PASSWORD }}`) or environment variables.

## 7.4 Optional deploy job (design only, not executed)

A job that runs only on `main`, after the first job succeeds, would apply migrations to a real environment with credentials from GitHub Secrets. A hosted runner cannot reach a laptop's Docker Postgres, so this is documented as a design and not run.

## 7.5 Status

**Not yet verified end to end.** The workflow file is committed, but the red/green runs on GitHub were not observed in this project's rehearsals (the CI tooling was not available locally). Check the Actions tab before presenting (see 8.1).

---

# 8. Fresh live demo: step-by-step script

Goal: demonstrate everything **from nothing**. No containers running, no data, no migrations applied, no scenario files staged. Total time about 25 minutes (about 3 for Part 1, 2 each for A to F, 4 for CI, 3 for wrap-up).

## 8.1 Preparation (not part of the demo)

These are environment checks, not demo state. Do them well before presenting.

1. The repository is cloned and **everything is committed** (`git status` shows a clean tree). `demo-reset` and the CI step depend on this.
2. Docker Desktop is installed. The first `up` downloads images (postgres:16, flyway/flyway:10, node:20-alpine) and builds the dashboard, which needs internet and takes a few minutes. Do one full `.\run.ps1 up` beforehand so the audience does not wait, then `.\run.ps1 down`.
3. Ports **5432** and **3000** are free (stop any local PostgreSQL).
4. The repository is pushed to GitHub with Actions enabled, and you can `git push` from the terminal.
5. A browser window for the dashboard and one for GitHub Actions. PowerShell open in the project folder.
6. **Rehearse the whole sequence once**, including the CI push.

## 8.2 Starting position (what the audience sees)

Docker Desktop running. Terminal empty. **No containers, no data.** Browser tab `http://localhost:3000/?present` shows "unable to connect" (nothing is running yet).

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\run.ps1 doctor
```

*Say:* "Before anything, a checklist." `doctor` prints that ports 5432 and 3000 are free and that the working tree is clean. It also confirms the demo files exist. (If it warns about uncommitted changes, commit first.)

## 8.3 Part 1: Create, apply, track (about 3 min)

*Concept:* a database is built from versioned files; Flyway tracks what has run.

**Step 1.1: start the system**
```powershell
.\run.ps1 down
.\run.ps1 up
```
*What happens:* `down` wipes any previous data (harmless if nothing exists). `up` starts PostgreSQL and the dashboard and waits for the health check. PostgreSQL creates `dev_db`, `test_db`, `prod_db` from the init script.
*Say:* "One command starts the whole environment."
*Show:* refresh the dashboard. All three environments show **Not initialised**, and every migration shows Pending. The databases exist but have no history yet.

**Step 1.2: look at what is pending**
```powershell
.\run.ps1 info
```
*Expected:* `Schema version: << Empty Schema >>` and a table of nine entries (V1 to V8 and the repeatable "order summary view"), all **Pending**.
*Say:* "These nine files exist in `sql/`; Flyway sees none of them applied."
*Screenshot:* all migrations Pending.

**Step 1.3: apply to dev**
```powershell
.\run.ps1 migrate
```
*Expected:* Flyway creates the `flyway_schema_history` table, applies V1 to V8 in order, then the repeatable migration, then runs the `afterMigrate` callback:
```
Creating Schema History table "public"."flyway_schema_history" ...
Migrating schema "public" to version "1 - create customers"
...
Migrating schema "public" to version "8 - add order status check"
Migrating schema "public" with repeatable migration "order summary view"
Successfully applied 9 migrations to schema "public", now at version v8
Executing SQL callback: afterMigrate
```
*Show:* dashboard, dev turns **In sync** (v8, 9 applied). Test and prod are still Not initialised.

**Step 1.4: confirm and inspect**
```powershell
.\run.ps1 info
.\run.ps1 history
```
*Expected:* `info` now shows all nine as **Success** with timestamps. `history` prints the table with rank, version, description, type, checksum, installed_by (`admin`), execution_time and `success = t`.
*Say:* "Every change is recorded permanently with a checksum of the file. That checksum is what protects history, as we will see in Scenario A."
*Screenshots:* all Success; the history table.

**Step 1.5: bring test and prod to the same schema**
```powershell
.\run.ps1 migrate-all
.\run.ps1 compare test
```
*Expected:* `migrate-all` prints `=== Migrating dev ===` ("up to date, no migration necessary"), then applies all nine to test and to prod. `compare test` prints `dev and test have identical migration history (9 entries).`
*Show:* the dashboard, all three **In sync**, matrix fully green. *Screenshot.*
*Say:* "Same files, three databases, identical outcome. This is what removes environment drift."

## 8.4 Scenarios A to F

Run them in this order. Each is a short command sequence (section 6 has the exact output). `.\run.ps1 scenario <letter>` prints the cheat card.

**Scenario A (about 2 min): someone edits an applied file**
```powershell
.\run.ps1 validate
Add-Content sql\V2__create_products.sql "-- harmless comment"
.\run.ps1 validate
.\run.ps1 migrate
git checkout sql/V2__create_products.sql
.\run.ps1 validate
```
*Say:* "We changed a file that is already applied, even just a comment. Flyway compares checksums and refuses, so history cannot be rewritten silently. Two ways out: revert the file, or `repair` if the change was deliberate."
*Point at:* the two checksums in the error. *Screenshot:* the failure, and the passing validate after the fix.

**Scenario B (about 2 min): a wrong migration that succeeded**
```powershell
.\run.ps1 stage B1
.\run.ps1 migrate
.\run.ps1 history
.\run.ps1 stage B2
.\run.ps1 migrate
.\run.ps1 psql
```
In psql: `\d customers`, then `\q`.
*Say:* "V9 has a typo, `phon`. It is valid SQL, so Flyway applies it and nothing fails. We do not edit V9. We add V10, which renames the column. History only grows. The free edition has no undo, so we roll forward."
*Show:* `\d customers` lists `phone`. Dashboard: dev is ahead of test and prod (V9, V10 Pending there).

**Scenario C (about 2 min): a migration with an error**
```powershell
.\run.ps1 stage C1
.\run.ps1 migrate
.\run.ps1 info
.\run.ps1 stage C2
.\run.ps1 migrate
.\run.ps1 migrate-all
```
*Say:* "A syntax error. Flyway reports it and says the changes were rolled back, because PostgreSQL treats schema changes as transactions. `info` shows V11 still Pending, so there is no half-applied state. We fix the file and run again. Then `migrate-all` brings test and prod level, so the next scenario starts clean."
*Show:* the dashboard shows V11 as Pending (a clean rollback leaves no failed row). *Screenshot:* the error and the Pending row.

**Scenario D (about 2 min): a repeatable migration changes**
```powershell
.\run.ps1 stage D
.\run.ps1 migrate
.\run.ps1 compare test
.\run.ps1 migrate-all
.\run.ps1 compare test
```
*Say:* "The view definition changed. Only that repeatable migration re-ran, because Flyway tracks its content, not a version number. Until test and prod catch up, they are different, and the dashboard shows it."
*Show:* test and prod turn **Drifted**, with "differs" on the view row; after `migrate-all` they clear.

**Scenario E (about 3 min): version conflict and out-of-order**
```powershell
.\run.ps1 stage E1
.\run.ps1 migrate
Rename-Item sql\V12__add_loyalty_tier.sql V13__add_loyalty_tier.sql
.\run.ps1 migrate
.\run.ps1 stage E3
.\run.ps1 migrate
.\run.ps1 migrate-ooo
.\run.ps1 info
```
*Say:* "Two developers both used V12. Flyway refuses to guess. We renumber one. Then a V12.5 arrives after V13 is already applied; validation fails because it is older than the current version. With out-of-order enabled it can be applied, and Flyway warns that this may not be reproducible, so it is a deliberate exception."
*Show:* `info` marks V12.5 **Out of Order**; the dashboard tags the cell "out of order".

**Scenario F (about 3 min): adopting a legacy database**
```powershell
.\run.ps1 demo-reset -Force
.\run.ps1 down
.\run.ps1 up
.\run.ps1 legacy
.\run.ps1 psql
.\run.ps1 migrate
.\run.ps1 baseline
.\run.ps1 info
.\run.ps1 stage F
.\run.ps1 migrate
```
In psql: `\dt` shows the tables, `\q` to leave.
*Say:* "First we clear the previous scenarios. Then we create a database someone built by hand, with real data and no Flyway history. Flyway refuses to touch a non-empty database it does not know. We baseline it at version 8, which says 'everything up to here already exists'. Only newer migrations run after that."
*Show:* `info` ("Below Baseline" rows plus a Baseline row); the dashboard shows V1 to V8 as **Baselined** and dev In sync.

## 8.5 CI pipeline (about 4 min, done live)

*Concept:* a pipeline proves migrations work from an empty database on every push.

**Step 5.1: show the workflow** (open `.github/workflows/flyway.yml`): "Start an empty Postgres, apply every migration, validate checksums, print the status."

**Step 5.2: push a broken migration (red run)**
```powershell
.\run.ps1 demo-reset -Force
git checkout -b broken-migration
.\run.ps1 stage C1
git add sql
git commit -m "Add broken migration"
git push -u origin broken-migration
```
Switch to the GitHub Actions tab. The run starts within seconds and fails in about a minute in the migrate step, with the syntax error and "Changes successfully rolled back". *Screenshot: red run.*

**Step 5.3: show a green run**
```powershell
git checkout main
```
(`main` has no broken file.) Trigger a run on `main`, either by pushing any commit, or:
```powershell
git commit --allow-empty -m "Trigger CI"
git push
```
Show the green run: migrate, validate and the `info` table in the job log. *Screenshot: green run.*

*Say:* "Green means the migrations work from scratch. Red means the change is blocked before it reaches any environment."

*Fallback:* if GitHub is slow, narrate while it runs, and show the workflow file and the `info` step output. Pushing the broken branch while you are still explaining Scenario F saves time, because the run happens in parallel.

## 8.6 Wrap-up (about 3 min)

```powershell
.\run.ps1 demo-reset -Force
```
*Say:* "One command returns everything to a clean, fully migrated state, so the demo can be repeated." *Show:* dashboard, dev, test and prod all In sync (9 applied). Switch back to the summary:

- Create: versioned files. Apply: same files to three environments. Track: history table with checksums, plus a live dashboard. Correct: six scenarios, never rewriting history. Automate: CI proves it from scratch on every push.
- Limits: Community edition rolls forward instead of undoing; one shared server; demo credentials.

## 8.7 Cheat sheet: demo order at a glance

```
Part 1:   doctor, down, up, info, migrate, info, history, migrate-all, compare test
A:        validate | edit V2 | validate | migrate | git checkout | validate
B:        stage B1, migrate, history, stage B2, migrate, psql
C:        stage C1, migrate (fails), info, stage C2, migrate, migrate-all
D:        stage D, migrate, compare test, migrate-all, compare test
E:        stage E1, migrate (fails), rename V12->V13, migrate, stage E3, migrate (fails), migrate-ooo, info
F:        demo-reset -Force, down, up, legacy, psql, migrate (fails), baseline, info, stage F, migrate
CI:       demo-reset -Force, branch, stage C1, commit, push (red), main, push (green)
Wrap-up:  demo-reset -Force
```

---

# 9. Report material

Written so each section can be pasted into the report. Chapter numbers follow the required outline. Replace each `[Screenshot: ...]` with an image from section 10.

## 9.1 Introduction

Application code is versioned, reviewed, tested and deployed automatically. Database structure often is not. When schema changes are applied by hand, environments drift apart (dev has a column that prod lacks), changes are lost or applied twice, and nobody can say which version a database is on. This project shows the alternative: every schema change is a numbered SQL file, applied automatically and in order, recorded permanently, and correctable without damaging history. It covers four actions (create, apply, track, correct) and two DevOps layers on top: automation through a CI pipeline, and observation through a live dashboard.

## 9.2 What Flyway is

(Use section 1.4. Add: Flyway applies the same DevOps principles to the database that version control and pipelines apply to code: the schema lives in version control, is built by a pipeline, and is identical in every environment.)

## 9.3 Manual SQL scripts versus Flyway

(Use the table in section 1.5.)

## 9.4 Architecture

(Use section 2.1 and 2.2. Include a diagram: Docker Compose containing postgres [dev_db, test_db, prod_db], flyway (on demand), dashboard; GitHub Actions separately with its own throwaway Postgres.) `[Screenshot: docker compose ps]`

## 9.5 Migration lifecycle

```
write file -> validate (checksums, duplicates, ordering) -> apply in a transaction -> record in flyway_schema_history -> afterMigrate callback
```

Each migration runs in its own transaction. PostgreSQL supports transactional DDL, so a failure rolls the whole migration back and leaves nothing half-applied (Scenario C). On success, one row is written with the version, a checksum of the file, the user, the time, the duration and the success flag.

## 9.6 Implementation: the schema

(Use section 3: the final structure, the migration table, the expected totals for the view, and the V5 limitation noted honestly.) The design principles are: one logical change per file; add nullable, backfill, then enforce (V4 and V5); seed data as its own migration (V7); constraints added after data exists (V8); a view as a repeatable migration; a callback for housekeeping.

## 9.7 Tracking

`info` shows what is pending or applied: before migrating, nine entries Pending; after, nine Success. `history` prints the history table:

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

Across environments, `compare` proves identical histories, and the dashboard (section 5) makes drift, pending work and failures visible at a glance. `[Screenshots: info before, info after, history table, dashboard in sync]`

## 9.8 Correction scenarios

(Use section 6 in full, A to F, including the real error output and the lesson for each.) `[Screenshots: failure and fix for each scenario]`

## 9.9 Automation

(Use section 7.) State clearly what the pipeline protects against: a migration that works on a developer's laptop but fails on an empty database, a syntax error, a duplicate version, or an edited applied file. `[Screenshots: red run, green run]`

## 9.10 Best practices

- Never edit an applied migration; add a new one.
- One logical change per file.
- Backfill before enforcing (add nullable, fill, then tighten).
- Roll forward instead of undoing.
- Keep secrets out of config files (environment variables, a secrets manager, GitHub secrets).
- Keep `clean` disabled outside dev.
- Validate in CI on every push.
- Detect drift by comparing environments.
- Treat out-of-order as a deliberate, documented exception.

## 9.11 Limitations

- Flyway Community has no undo migrations, dry runs or advanced drift detection. These are paid features, so recovery here is by rolling forward.
- Dev, test and prod share one PostgreSQL server for simplicity. In real life they would be separate servers.
- Credentials are demo values.
- The dashboard is read-only and records no history beyond what Flyway stores. A cleanly rolled-back failure leaves no row, so it appears as Pending.
- The "out of order" and "Baselined" labels on the dashboard are derived from the history table, not from Flyway's own `info` logic.
- The deploy job in CI is a design, not executed.

## 9.12 Conclusion

Schema changes were written as versioned files, applied identically to three environments, tracked in a permanent history table, and corrected safely in six different failure situations. A pipeline proves the migrations from scratch on each push, and a read-only dashboard makes the state of every environment visible during the demonstration. The whole system returns to a clean state with a single command, so the demonstration can be repeated.

---

# 10. Screenshot checklist

Save in `docs/screenshots/`, named as below.

| # | File | Capture | When |
|---|---|---|---|
| 1 | `01-info-pending.png` | `info` with all nine Pending | Step 1.2 |
| 2 | `02-info-success.png` | `info` after migrate, all Success | Step 1.4 |
| 3 | `03-history.png` | `history` table | Step 1.4 |
| 4 | `04-dashboard-uninitialised.png` | Dashboard right after `up` | Step 1.1 |
| 5 | `05-dashboard-in-sync.png` | Dashboard, dev/test/prod In sync | Step 1.5 |
| 6 | `06-compare-identical.png` | `compare test` identical | Step 1.5 |
| 7 | `07-A-fail.png`, `07-A-fix.png` | Checksum mismatch, then passing validate | Scenario A |
| 8 | `08-B-history.png`, `08-B-describe.png` | History with V9, V10; `\d customers` | Scenario B |
| 9 | `09-C-error.png`, `09-C-pending.png` | Rolled-back error; V11 Pending | Scenario C |
| 10 | `10-D-drift.png` | Dashboard with "differs" on test/prod | Scenario D |
| 11 | `11-E-duplicate.png`, `11-E-validate.png`, `11-E-ooo.png` | Duplicate version; V12.5 validation error; Out of Order | Scenario E |
| 12 | `12-F-refused.png`, `12-F-baselined.png` | Non-empty refusal; Baselined dashboard + `info` | Scenario F |
| 13 | `13-ci-red.png`, `13-ci-green.png` | GitHub Actions red and green runs | CI |

---

# 11. Troubleshooting and risks

| Symptom | Cause and fix |
|---|---|
| "Docker is not running" | Start Docker Desktop and wait until it reports running. |
| `run.ps1` cannot be loaded (execution policy) | `Set-ExecutionPolicy -Scope Process Bypass` in each new PowerShell window. |
| Port 5432 or 3000 already in use | Stop local PostgreSQL or whatever uses the port. `doctor` checks this when the stack is down. |
| `demo-reset` says "Uncommitted changes in sql/ would be lost" | Commit them, or use `demo-reset -Force` to discard them (normal after a scenario). |
| Leftover scenario files (V9 and above) in `sql/` show as Pending | `demo-reset` removes untracked files in `sql/`. |
| Flyway ignores or rejects a file | Check the name: capital `V`, **two** underscores. |
| `clean` is refused on test or prod | Intended: `cleanDisabled` is only off in dev. |
| First `up` is slow | It is pulling images and building the dashboard. Do this before presenting. |
| A scenario's output differs from this file | Flyway wording can change between versions. This file was verified on 10.22.0. |
| "A more recent version of Flyway is available" | Harmless banner printed on every command. |
| Dashboard shows "Dashboard server unreachable" | The dashboard container is not running: `.\run.ps1 up`. |
| Commit/line-ending warnings from git | `LF will be replaced by CRLF` is harmless. Flyway's checksum ignores line endings. |

Risks to manage before presenting:

- **Uncommitted changes.** `demo-reset` restores `sql/` from git; uncommitted migration edits would be lost.
- **CI not yet observed.** Push once beforehand and read the Actions logs.
- **Network.** Needed for image pulls (first run) and for pushing to GitHub.

---

# 12. Status, open items and glossary

## 12.1 What is verified

On this repository, in order, on Flyway 10.22.0 / PostgreSQL 16.15: fresh start, `info`, `migrate`, `migrate-all`, `history`, `compare`, `doctor`, `scenario`, `demo-reset` (including the uncommitted-changes guard and `-Force`), and scenarios A, B, C, D, E and F with the outputs shown. The dashboard was checked through its API for Not initialised, In sync, Drifted (checksum mismatch), Baselined and Out-of-order states.

## 12.2 Open items

1. **CI red and green runs** on GitHub have not been observed; do them once and capture screenshots (section 10).
2. **Screenshots** have not been taken.
3. **Dashboard visuals** (presentation mode, the "Changed" indicator) were not viewed in a browser, only checked through the served code and API; look at them once.
4. **V5 backfill** is a no-op on a fresh database (see 3.2). Decide whether to leave it and state it, or seed rows earlier (changes checksums of pushed files).
5. **Makefile** was updated to match `run.ps1` but not executed (no `make` on this Windows machine).
6. **Final report and slides** are produced from section 9 of this file.

## 12.3 Glossary

| Term | Meaning |
|---|---|
| Migration | A SQL file that changes the schema |
| Versioned migration | `V<n>__name.sql`; runs once, in order |
| Repeatable migration | `R__name.sql`; re-runs when its content changes |
| Callback | A script Flyway runs at a defined point, such as `afterMigrate.sql` |
| History table | `flyway_schema_history`; Flyway's record of what has run |
| Checksum | A hash of a file's content, stored when the file is applied |
| Validate | Compare applied migrations with files on disk |
| Repair | Update stored checksums and remove failed entries |
| Baseline | Declare an existing database to be at a given version |
| Out-of-order | Apply a migration with a lower version than the current one |
| Drift | Two environments whose applied migrations differ |
| Roll forward | Fix a mistake with a new migration rather than undoing |
| Clean | Drop everything in a database; allowed only in dev |
| Transactional DDL | Schema changes that roll back on failure (PostgreSQL) |
