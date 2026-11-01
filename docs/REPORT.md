# Automated Database Schema Versioning and Migration with Flyway, PostgreSQL and a CI/CD Pipeline

DevOps project report. Tool: Flyway Community 10.22. Databases: PostgreSQL 17 on Supabase (dev, test and prod as three schemas); PostgreSQL 16 for the pipeline's gate and an optional local sandbox. Pipeline: GitHub Actions.

> Screenshot placeholders are written as `[Screenshot: ...]`. Save images in `docs/screenshots/` and replace each placeholder with `![caption](screenshots/file.png)`.
>
> Status: the pipeline's first full deployment (gate, dev, test, prod all green) has been observed. The six scenarios have been verified on the local sandbox; their runs through the pipeline are still to be rehearsed (see PROJECT.md section 12).

---

## 1. Introduction

Application code is versioned, reviewed, tested and deployed automatically. Database structure often is not. When schema changes are applied by hand, four problems appear:

1. **Environment drift.** Dev has a column that prod lacks, and nobody notices until a release fails.
2. **Lost or repeated changes.** A script is forgotten, or run twice.
3. **No answer to "what version is this database?"**
4. **Deployment depends on a person.** Whoever has the terminal and the credentials decides what reaches prod.

This project shows the alternative: every schema change is a numbered SQL file committed to version control, validated and applied by a CI/CD pipeline in a fixed order, recorded permanently, and correctable without damaging history. It covers four actions: **create, apply, track, correct**. On top sit two DevOps layers: **automate** (a pipeline that decides success or failure) and **observe** (run logs and a read-only dashboard).

## 2. What Flyway is

Flyway is a migration tool. It looks at a folder of SQL files named `V<version>__<description>.sql`, compares them with a table inside the database called `flyway_schema_history`, and applies whichever files have not been applied yet, in version order.

Key ideas:

- **Versioned migrations** (`V1__...`) run exactly once, in order.
- **Repeatable migrations** (`R__...`) re-run whenever their content changes. Used here for a view.
- **Callbacks** (`afterMigrate.sql`) run at defined points. Used here to refresh planner statistics after each migrate.
- **Checksums.** Flyway stores a checksum of every applied file. If an applied file is later edited, `validate` and `migrate` refuse to continue.
- **Baseline** puts an existing, never-managed database under version control at a chosen version.
- **Out-of-order** lets Flyway apply a migration whose version is lower than one already applied.

This is DevOps practice applied to databases: the schema lives in version control, is built by a pipeline, and is identical in every environment.

## 3. Manual SQL scripts versus Flyway, and manual commands versus a pipeline

| Concern | Manual scripts | Flyway |
|---|---|---|
| Traceability | A person remembers what ran | `flyway_schema_history` records version, checksum, user, time, duration, success |
| Repeatability | Depends on who runs what, in which order | Same files give the same result on any empty database |
| Consistency | Environments drift | Dev, test and prod receive identical files |
| Error detection | Edited or missing scripts go unnoticed | Checksum validation blocks changed history |
| Automation | Hard to put in a pipeline | One command, usable in CI |
| Collaboration | Two people pick the same script number silently | Duplicate or out-of-order versions are detected |

| Concern | Commands run by hand | Pipeline |
|---|---|---|
| Who deploys | Whoever has the terminal and credentials | The pipeline, with credentials held as GitHub secrets |
| Bad change reaches an environment | Possible | Not possible: it must apply to an empty database first |
| Order of environments | Remembered | Enforced: dev, then test, then prod, stopping at the first failure |
| Evidence | Terminal scrollback | A permanent, shareable Actions log per run |
| Approval | None | Optional required reviewer before an environment |

## 4. Architecture

| Component | Role |
|---|---|
| GitHub repository | Holds the migration files in `sql/` and the workflows. A push or pull request starts the pipeline. |
| `flyway.yml` | The main pipeline: a gate job, then dev, test and prod deployment jobs. |
| `_deploy.yml` | A reusable job that runs `info`, `validate`, `migrate`, `info` against one environment. |
| `manual.yml` | A manually started workflow for operations the pipeline never runs automatically: repair, baseline, out-of-order migrate, reset. |
| GitHub Environments `dev`, `test`, `prod` | Each holds its own secrets (`DB_URL`, `DB_USER`, `DB_PASSWORD`); `prod` can require approval. |
| Supabase PostgreSQL 17 | One database with three schemas, `dev`, `test`, `prod`, each with its own `flyway_schema_history`. Reached through the Session pooler (the direct host is IPv6-only and GitHub runners are IPv4). |
| Gate database | A throwaway PostgreSQL 16 service container, created for each run and discarded. |
| Dashboard | A Node web server that reads the history tables and migration files and serves a read-only page. |
| Local sandbox (optional) | A Docker Compose stack (Postgres, Flyway, dashboard) used to rehearse scenarios without touching the cloud. |

Flyway is configured on the command line by the pipeline: `-url`, `-user`, `-password` from the Environment secrets, `-schemas=<environment>`, and `-validateMigrationNaming=true`. Flyway 10 disables `clean` by default; only the manual `reset-schema` action enables it, after a typed confirmation.

`[Screenshot: Actions run graph showing the gate, dev, test and prod jobs]`

## 5. Migration lifecycle

```
write file -> commit and push -> gate (empty DB) -> per environment: validate (checksums, ordering, duplicates)
        -> apply pending files in version order, each in its own transaction
        -> insert a row into flyway_schema_history (version, checksum, user, time, success)
        -> run afterMigrate callback
```

PostgreSQL supports transactional DDL, so a migration that fails part-way is rolled back completely. No half-applied state is left behind (Scenario C).

## 6. Implementation: the schema

An order-management schema that grows through eight versions. In the cloud each environment's tables live in its own schema (`dev.customers`, `test.customers`, `prod.customers`).

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

Verification: with the seed data the view returns totals of 6097.00 (order 1), 4999.00 (order 2) and 2299.00 (order 3). V5's backfill is a no-op on a fresh database because `customers` is still empty when it runs (the seed data arrives in V7); the pattern is correct, but the demonstration does not show rows being rewritten.

## 7. Tracking

The Actions log of each deployment shows Flyway's `info` table before and after `migrate`: nine entries Pending, then nine Success. Each environment's history table can be read in Supabase:

```sql
select installed_rank, version, description, type, checksum, installed_by, execution_time, success
from dev.flyway_schema_history order by installed_rank;
```

`[Screenshot: info before the first deployment, all Pending]`
`[Screenshot: info after, all Success]`

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

Identical histories across environments are proved by a query that compares two schemas and returns no rows when they match (PROJECT.md section 4.4).

`[Screenshot: the three schemas in the Supabase Table Editor]`
`[Screenshot: history table]`

### The dashboard

A read-only page that refreshes every three seconds and never writes to any database. It shows an environment card for each environment (version, applied/pending/failed counts, status badge), a one-line health banner, a migration matrix (every file against every environment, with "differs" and "out of order" tags), and a tabbed view of the live history table. Press `P` for a presentation mode with larger text. Statuses: In sync, Pending, Drifted, Failed, Not initialised, Unreachable; cells can also read Baselined. It can read either the local sandbox or the Supabase schemas, selected by environment variables.

## 8. Correction scenarios

Each scenario is run by staging a file, committing and pushing, then reading the pipeline result. The Flyway messages below were captured on the local sandbox; in the pipeline they appear in the job logs with the schema name `"dev"`, `"test"` or `"prod"` instead of `"public"`.

### A. Checksum mismatch (applied history is protected)
A comment is appended to the already-applied `V2` and pushed. The gate passes (an empty database has no stored checksum), but `dev` fails at Validate, and `test` and `prod` are skipped:
```
ERROR: Validate failed: Migrations have failed validation
Migration checksum mismatch for migration version 2
-> Applied to database : 981205911
-> Resolved locally    : 1302983372
Either revert the changes to the migration, or run repair to update the schema history.
```
**Fix:** revert the commit. If the change was intentional and harmless, the manual `repair` action updates the stored checksum, once per environment.
**Lesson:** applied history cannot be silently rewritten, and the pipeline enforces this in every environment.

### B. A wrong migration that succeeded (roll forward)
V9 adds a column misspelled `phon`. It is valid SQL, so the pipeline is green and the typo reaches all three environments. The file is not edited; V10 renames the column to `phone`.
**Lesson:** history is append-only. Flyway Community has no undo, so mistakes are fixed by rolling forward. A pipeline proves a migration applies; it cannot judge whether valid SQL is correct.

### C. A failed migration
V11 contains `ALTER TABL`. The gate fails; `dev`, `test` and `prod` are skipped, so the broken file never reaches a real environment:
```
ERROR: Migration of schema "public" to version "11 - add loyalty points" failed! Changes successfully rolled back.
Message : ERROR: syntax error at or near "TABL"
```
After correcting the file and pushing again, all four jobs are green.
**Lesson:** on PostgreSQL a failed migration leaves nothing half-applied, and the gate stops a bad file before any real environment sees it.

### D. A repeatable migration changes
The view file gains an `item_count` column. Each environment re-applies only that migration; the old history row becomes Superseded. With a required reviewer on `test` or `prod`, the run pauses and the environments differ until it is approved.
**Lesson:** repeatable migrations track content, not version numbers.

### E. Version conflict and out-of-order
Two files are both numbered V12; the gate fails:
```
ERROR: Found more than one migration with version 12
```
One is renumbered to V13 and both apply. Then a file numbered V12.5 arrives after V13 is applied. The gate passes (on an empty database it simply applies in order), but `dev` fails validation:
```
ERROR: Validate failed: Migrations have failed validation
Detected resolved migration not applied to database: 12.5.
To ignore this migration, set -ignoreMigrationPatterns='*:ignored'. To allow executing this migration, set -outOfOrder=true.
```
The manual `migrate-out-of-order` action applies it, once per environment, and `info` marks it `Out of Order`.
**Lesson:** parallel work creates numbering conflicts. The pipeline's validate step ignores only pending migrations, so a skipped-over version is still caught. Out-of-order is a deliberate exception, and Flyway warns that the result "may not be reproducible".

### F. Baselining an existing database
In the manual workflow, a schema is emptied (`reset-schema`) and filled with a hand-built legacy schema that has no Flyway history (`load-legacy-schema`). `migrate` refuses:
```
ERROR: Found non-empty schema(s) "public" but no schema history table. Use baseline() or set baselineOnMigrate to true...
```
`baseline` marks it as version 8. `info` shows V1 to V8 as Below Baseline; pushing V9 then applies only V9 and the repeatable view.
**Lesson:** an existing database can be brought under version control without rebuilding it. Baselining is a one-off operation, so it is deliberately a manual action rather than part of the automatic pipeline.

`[Screenshots: failure and fix for each of A to F]`

## 9. Automation: the CI/CD pipeline

The main workflow `flyway.yml` runs on pushes to `main`, on pull requests and on manual dispatch:

1. **Gate (`migrate-from-scratch`).** A throwaway PostgreSQL 16 service is started, then Flyway runs `migrate`, `validate` and `info` against the empty database.
2. **dev, test, prod.** Each deployment job runs only on `main`, needs the previous job to succeed, and calls the reusable `_deploy.yml`, which runs under the GitHub Environment of the same name and executes `info`, `validate`, `migrate`, `info`.
3. **Stop at the first failure.** If the gate or dev fails, the later jobs are skipped.

The validate step ignores *pending* migrations (`-ignoreMigrationPatterns=*:pending`). A plain `validate` treats every not-yet-applied migration as an error, which failed the very first deployment to an empty environment; this was the first real failure of the pipeline and was fixed. Everything else, including edited applied files and skipped-over versions, still fails validation.

A pull request runs only the gate, so a broken change can be shown failing without anything being deployed. Required reviewers on an Environment add a manual approval before it.

Operations that change history or discard data are never automatic. The manual workflow `manual.yml` offers `info`, `migrate`, `migrate-out-of-order`, `repair`, `baseline`, `load-legacy-schema` and `reset-schema`. `repair` and `reset-schema` require the environment name typed as confirmation, and `load-legacy-schema` is blocked on prod.

The pipeline protects against a migration that works on a developer's laptop but fails on an empty database, a syntax error, a duplicate version, an edited applied file, a skipped-over version, and a bad change reaching prod because dev already failed. It does not protect against a migration that is valid SQL but wrong (Scenario B).

`[Screenshot: red gate run with skipped deployment jobs]`
`[Screenshot: green run, all four jobs]`
`[Screenshot: approval gate waiting on prod]`

## 10. Best practices demonstrated

- Never edit an applied migration; add a new one.
- One logical change per file.
- Backfill before enforcing (V4 and V5: add nullable, fill, then tighten).
- Roll forward instead of undoing.
- Keep secrets out of the repository: GitHub Environment secrets, separate per environment.
- Keep `clean` disabled by default; require a typed confirmation to enable it.
- Validate on an empty database on every push, before any real environment.
- Deploy in order and stop at the first failure.
- Deploy only from `main`; use pull requests to run the gate without deploying.
- Require approval before prod.
- Detect drift by comparing environments.
- Treat out-of-order as a deliberate, documented exception.

## 11. Limitations

- Flyway Community has no undo migrations, dry runs or advanced drift detection. Those are paid features; recovery here is by rolling forward.
- Dev, test and prod are three schemas in one Supabase database and share a database user. In real life they would be separate databases with separate credentials.
- The pipeline can prove that a migration applies, not that it is correct.
- Every scenario step is a commit and a pipeline run, which is slower than commands at a terminal.
- Applied migrations cannot be un-applied. Between demonstration runs the schemas must be reset with the manual workflow and `sql/` restored from git.
- The dashboard is deliberately read-only and records no history beyond what Flyway stores. A cleanly rolled-back failure leaves no row, so it appears as Pending.
- The out-of-order flag and Baselined state on the dashboard are derived from the history table, not from Flyway's own `info` logic.

## 12. Conclusion

Schema changes were written as versioned files, validated on an empty database, applied by a pipeline to three environments in order, tracked in a permanent history table, and corrected safely in six different failure situations. The pipeline, not a person at a terminal, decides success or failure, and it stops the rollout at the first failing environment. A small manual workflow covers the operations that must never run automatically, and the demonstration can be reset and repeated by restoring `sql/` from a baseline tag and rebuilding the schemas.
