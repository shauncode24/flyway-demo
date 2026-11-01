# Automated Database Schema Versioning and Migration with Flyway and PostgreSQL

DevOps project report. Tool: Flyway Community 10.22 on PostgreSQL 16. Environment: Docker Compose, GitHub Actions.

> Screenshot placeholders are written as `[Screenshot: ...]`. Save images in `docs/screenshots/` and replace each placeholder with `![caption](screenshots/file.png)`.

---

## 1. Introduction

Application code is versioned, reviewed, tested and deployed automatically. Database structure often is not. When schema changes are applied by hand, three problems appear:

1. **Environment drift.** Dev has a column that prod lacks, and nobody notices until a release fails.
2. **Lost or repeated changes.** A script is forgotten, or run twice.
3. **No answer to "what version is this database?"**

This project shows the alternative: every schema change is a numbered SQL file, applied automatically and in order, recorded permanently, and correctable without damaging history. It covers four actions: **create, apply, track, correct**. On top sit two DevOps layers: **automate** (a CI pipeline) and **observe** (a live dashboard).

## 2. What Flyway is

Flyway is a migration tool. It looks at a folder of SQL files named `V<version>__<description>.sql`, compares them with a table inside the database called `flyway_schema_history`, and applies whichever files have not been applied yet, in version order.

Key ideas:

- **Versioned migrations** (`V1__...`) run exactly once, in order.
- **Repeatable migrations** (`R__...`) re-run whenever their content changes. Used here for a view.
- **Callbacks** (`afterMigrate.sql`) run at defined points. Used here to refresh planner statistics after each migrate.
- **Checksums.** Flyway stores a checksum of every applied file. If an applied file is later edited, `validate` and `migrate` refuse to continue.

This is DevOps practice applied to databases: the schema lives in version control, is built by a pipeline, and is identical in every environment.

## 3. Manual SQL scripts versus Flyway

| Concern | Manual scripts | Flyway |
|---|---|---|
| Traceability | A person remembers what ran | `flyway_schema_history` records version, checksum, user, time, duration, success |
| Repeatability | Depends on who runs what, in which order | Same files give the same result on any empty database |
| Consistency | Environments drift | Dev, test and prod receive identical files |
| Error detection | Edited or missing scripts go unnoticed | Checksum validation blocks changed history |
| Automation | Hard to put in a pipeline | One command, usable in CI |
| Collaboration | Two people pick the same script number silently | Duplicate or out-of-order versions are detected |

## 4. Architecture

Three containers, managed by Docker Compose:

| Service | Role |
|---|---|
| `postgres` | PostgreSQL 16 hosting `dev_db`, `test_db`, `prod_db`, created on first start by an init script. Health check ensures other services wait until initialisation has finished. |
| `flyway` | Flyway 10, started on demand with one config file per environment. |
| `dashboard` | Node web server on port 3000. Reads each environment's history table and the migration files and serves a live, read-only page. |

A GitHub Actions workflow runs separately: it starts a throwaway PostgreSQL service on every push, then migrates, validates and prints `info`.

Configuration is one `.conf` file per environment. Only the dev config sets `cleanDisabled=false`, because Flyway disables `clean` by default as a safety feature.

`[Screenshot: docker compose ps showing postgres and dashboard healthy]`

## 5. Migration lifecycle

```
write V<n>__name.sql  ->  Flyway reads history table  ->  validate (checksums, ordering, duplicates)
        ->  apply pending files in version order, each in its own transaction
        ->  insert a row into flyway_schema_history (version, checksum, user, time, success)
        ->  run afterMigrate callback
```

PostgreSQL supports transactional DDL, so a migration that fails part-way is rolled back completely. No half-applied state is left behind (Scenario C).

## 6. Implementation: the schema

An order-management schema that grows through eight versions.

| Version | Change | Concept |
|---|---|---|
| V1 | Create `customers` | Basic table creation |
| V2 | Create `products` (price must not be negative) | Constraints |
| V3 | Create `orders` and `order_items` | Foreign keys, cascade delete |
| V4 | Add nullable `email` to `customers` | Evolving an existing table |
| V5 | Backfill emails, then make `email` required and unique | Data migration: add nullable, backfill, enforce |
| V6 | Indexes on foreign-key columns | Performance |
| V7 | Seed data: 3 customers, 3 products, 3 orders, 4 items | Seed data |
| V8 | Check constraint on order status (NEW, PAID, SHIPPED, CANCELLED) | Rule on existing data |
| R__ | `order_summary` view | Repeatable migration |
| afterMigrate | `ANALYZE` | Callback |

Verification: with the seed data the view returns totals of 6097.00 (order 1), 4999.00 (order 2) and 2299.00 (order 3).

## 7. Tracking

`./run.ps1 info` shows what is pending or applied. Before migrating, all nine entries are Pending; after, all are Success.

`[Screenshot: info before migrate, all Pending]`
`[Screenshot: info after migrate, all Success]`

`./run.ps1 history` prints the history table:

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

`./run.ps1 migrate-all` applies dev, test and prod in that order and stops at the first failure. `./run.ps1 compare test` then proves the histories are identical.

`[Screenshot: history table]`
`[Screenshot: dashboard with dev, test and prod all In sync]`

### The dashboard

A read-only page that refreshes every three seconds and never writes to any database. It shows an environment card for each database (version, applied/pending/failed counts, status badge), a one-line health banner, a migration matrix (every file against every environment, with "differs" and "out of order" tags), and a tabbed view of the live history table. Press `P` for a presentation mode with larger text. Statuses: In sync, Pending, Drifted, Failed, Not initialised, Unreachable. Cells can also read Baselined.

## 8. Correction scenarios

All six were run on this setup, and the behaviour below is the actual Flyway output.

### A. Checksum mismatch (applied history is protected)
A comment is appended to the already-applied `V2`. `validate` and `migrate` both fail:
```
ERROR: Validate failed: Migrations have failed validation
Migration checksum mismatch for migration version 2
-> Applied to database : 981205911
-> Resolved locally    : 1302983372
Either revert the changes to the migration, or run repair to update the schema history.
```
**Fix:** revert the file (`git checkout`). If the change was intentional and harmless, `repair` updates the stored checksum.
**Lesson:** applied history cannot be silently rewritten.

### B. A wrong migration that succeeded (roll forward)
V9 adds a column misspelled `phon`. It is valid SQL, so it applies. The file is not edited; V10 renames the column to `phone`.
**Lesson:** history is append-only. Flyway Community has no undo, so mistakes are fixed by rolling forward.

### C. A failed migration
V11 contains `ALTER TABL`:
```
ERROR: Migration of schema "public" to version "11 - add loyalty points" failed! Changes successfully rolled back.
Message : ERROR: syntax error at or near "TABL"
```
`info` still shows V11 as Pending. After correcting the file, `migrate` succeeds.
**Lesson:** on PostgreSQL a failed migration leaves nothing half-applied. (The dashboard shows it as Pending, because no failed row is stored; the error itself appears in the terminal.)

### D. A repeatable migration changes
The view file gains an `item_count` column. Migrating dev re-applies only that migration; the old history row becomes Superseded. Until the other environments are migrated, `compare test` reports the difference and the dashboard shows "differs" on test and prod. `migrate-all` brings them level.
**Lesson:** repeatable migrations track content, not version numbers.

### E. Version conflict and out-of-order
Two files are both numbered V12:
```
ERROR: Found more than one migration with version 12
```
One is renumbered to V13 and both apply. Then a file numbered V12.5 arrives after V13 is applied:
```
ERROR: Validate failed: Migrations have failed validation
Detected resolved migration not applied to database: 12.5.
To ignore this migration, set -ignoreMigrationPatterns='*:ignored'. To allow executing this migration, set -outOfOrder=true.
```
`migrate-ooo` applies it, and `info` marks it `Out of Order`.
**Lesson:** parallel work creates numbering conflicts. Out-of-order is a deliberate exception, and Flyway warns that the result "may not be reproducible".

### F. Baselining an existing database
A hand-built schema with no Flyway history is created in dev. `migrate` refuses:
```
ERROR: Found non-empty schema(s) "public" but no schema history table. Use baseline() or set baselineOnMigrate to true...
```
`baseline` marks it as version 8. `info` shows V1 to V8 as Below Baseline; only V9 and the repeatable view then run.
**Lesson:** an existing database can be brought under version control without rebuilding it.

`[Screenshots: failure and fix for each of A to F]`

## 9. Automation

The workflow `.github/workflows/flyway.yml` runs on every push and pull request:

1. Start a throwaway PostgreSQL 16 service with a health check.
2. Check out the repository.
3. `migrate` against the empty database.
4. `validate` the checksums.
5. `info`, so the migration table appears in the job log.

A green run proves the migrations work from nothing. A red run (for example from a branch containing the broken Scenario C file) blocks the change before it reaches any environment.

Credentials in this repository are demo values. Real projects supply them through GitHub Actions secrets (`${{ secrets.DB_PASSWORD }}`) or environment variables, never through committed files. A deploy job that runs only on `main` after the first job succeeds would follow the same pattern; it is a design, not executed here, because a hosted runner cannot reach a laptop's Docker.

`[Screenshot: red CI run on the broken-migration branch]`
`[Screenshot: green CI run on main]`

## 10. Best practices demonstrated

- Never edit an applied migration; add a new one.
- One logical change per file.
- Backfill before enforcing (V4 and V5: add nullable, fill, then tighten).
- Roll forward instead of undoing.
- Keep secrets out of config files.
- Keep `clean` disabled outside dev.
- Validate in CI on every push.
- Detect drift by comparing environments (`compare`, dashboard).

## 11. Limitations

- Flyway Community has no undo migrations, dry runs or advanced drift detection. Those are paid features; recovery here is by rolling forward.
- Dev, test and prod share one PostgreSQL server for simplicity. In real life they would be separate servers.
- Credentials are demo values.
- The dashboard is deliberately read-only and records no history beyond what Flyway stores. A cleanly rolled-back failure leaves no row, so it appears as Pending.
- The out-of-order flag and Baselined state are derived from the history table, not from Flyway's own `info` logic.

## 12. Conclusion

Schema changes were written as versioned files, applied identically to three environments, tracked in a permanent history table, and corrected safely in six different failure situations. A pipeline proves the migrations from scratch on each push, and a read-only dashboard makes the state of every environment visible during the demonstration. The whole system returns to a clean state with a single command (`./run.ps1 demo-reset`), so the demonstration can be repeated.
