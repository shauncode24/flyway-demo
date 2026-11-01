# Live Demo Runbook (CI/CD pipeline version)

Short runbook. The full reference, expected output and explanations are in [PROJECT.md](PROJECT.md) (section 8 is this runbook in detail; section 6 has each scenario's output).

How it works: you **stage** a migration file, **commit and push** it, and the GitHub Actions pipeline decides the result. Keep three tabs open: the repo's **Actions** tab, Supabase **Table Editor / SQL Editor**, and a PowerShell window in the project folder.

`[Actions]` below means a click in GitHub: Actions tab, **Manual Flyway operations**, Run workflow, pick `environment` and `action`.

## Before the audience arrives
1. `git status` is clean and `sql/` holds V1 to V8, the view and the callback only.
2. Supabase has the empty-or-baseline schemas `dev`, `test`, `prod`. GitHub Environments `dev`, `test`, `prod` each have the secrets `DB_URL`, `DB_USER`, `DB_PASSWORD`.
3. The tag `demo-baseline` exists on the commit where `sql/` is V1 to V8 only (`git tag demo-baseline; git push origin demo-baseline`).
4. Do one complete rehearsal of this document, including the reset at the end.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\run.ps1 doctor
```

`.\run.ps1 scenario <A-F>` prints the cheat card for a scenario.

---

## Part 1: Create, apply, track
1. `[Actions]` environment `dev`, action `info`: all nine entries **Pending** (or nothing applied yet).
2. Actions tab, **Flyway migrations**, Run workflow on `main` (or `git commit --allow-empty -m "Deploy baseline"; git push`).
   Watch `migrate-from-scratch`, then `dev`, `test`, `prod` turn green in order.
3. Open the `dev` job log: the **After** step shows all nine **Success**.
4. Supabase: Table Editor, switch the schema between `dev`, `test`, `prod`. SQL Editor history query:
   ```sql
   select installed_rank, version, description, checksum, installed_by, success
   from dev.flyway_schema_history order by installed_rank;
   ```
5. Identical environments (no rows means identical):
   ```sql
   (select version, description, checksum from dev.flyway_schema_history
    except select version, description, checksum from test.flyway_schema_history)
   union all
   (select version, description, checksum from test.flyway_schema_history
    except select version, description, checksum from dev.flyway_schema_history);
   ```

## Scenario A: checksum mismatch
```powershell
Add-Content sql\V2__create_products.sql "-- harmless comment"
git add sql; git commit -m "Edit applied V2"; git push
```
`[Actions]` result: gate green, `dev` **red** at Validate (checksum mismatch), `test` and `prod` skipped.
Fix: `git revert HEAD --no-edit; git push` (green).
Optional repair path: keep the edit, `[Actions]` `repair` on `dev` with `confirm` = `dev`, re-run the failed run; repeat for `test` and `prod`.

## Scenario B: wrong migration, roll forward
```powershell
.\run.ps1 stage B1          # V9 with a typo: column "phon"
git add sql; git commit -m "Add phone"; git push      # green: valid SQL, typo is now everywhere
.\run.ps1 stage B2          # V10 renames phon to phone
git add sql; git commit -m "Fix phone column"; git push   # green
```
Show in Supabase:
```sql
select column_name from information_schema.columns
where table_schema = 'dev' and table_name = 'customers' order by ordinal_position;
```
Point out: V9 is never edited. History is append-only; Community edition has no undo.

## Scenario C: failed migration
```powershell
.\run.ps1 stage C1          # V11 with a syntax error
git add sql; git commit -m "Add loyalty points"; git push
```
Gate **red** ("Changes successfully rolled back"); `dev`, `test`, `prod` **skipped**: the broken file never reaches a real environment.
```powershell
.\run.ps1 stage C2          # overwrites V11 with the corrected file
git add sql; git commit -m "Fix V11"; git push      # green
```
Optional: push C1 to a branch and open a **pull request** to show the red gate without anything on `main`.

## Scenario D: repeatable migration
```powershell
.\run.ps1 stage D           # view gets a new column
git add sql; git commit -m "Add item_count to view"; git push
```
Green; only the repeatable migration is re-applied (the log's `info` shows the old view row **Superseded**).
With Required reviewers on `test` or `prod`, the run pauses after `dev`: run the compare query from Part 1 step 5 (not empty), approve, run it again (empty).

## Scenario E: version conflict and out-of-order
```powershell
.\run.ps1 stage E1          # two files both numbered V12
git add sql; git commit -m "Two V12 files"; git push       # gate RED: duplicate version
Rename-Item sql\V12__add_loyalty_tier.sql V13__add_loyalty_tier.sql
git add sql; git commit -m "Renumber to V13"; git push     # green
.\run.ps1 stage E3          # V12.5: lower than the applied V13
git add sql; git commit -m "Add V12.5"; git push           # gate green, dev RED at Validate
```
Then `[Actions]` `migrate-out-of-order` on `dev`, then `test`, then `prod`. Re-run **Flyway migrations** on `main`: green.
Point out: Flyway warns out-of-order "may not be reproducible"; it is a deliberate exception.

## Scenario F: baselining an existing database
Start from the baseline state (see Reset below, so `sql/` is V1 to V8). **Do not push until the last step.**
1. `[Actions]` `dev` / `reset-schema` (`confirm` = `dev`)
2. `[Actions]` `dev` / `load-legacy-schema` (Supabase: tables in `dev`, no `flyway_schema_history`)
3. `[Actions]` `dev` / `migrate`: **red on purpose** (non-empty schema, no history)
4. `[Actions]` `dev` / `baseline`, `baseline_version` = `8`
5. `[Actions]` `dev` / `info`: V1 to V7 **Below Baseline**, a **Baseline** row at version 8
6. ```powershell
   .\run.ps1 stage F          # V9 adds customers.phone
   git add sql; git commit -m "Add phone"; git push
   ```
   Green: `dev` applies only V9 and the view.

## Reset (replaces demo-reset)
Applied migrations stay applied, so to start again:
1. `[Actions]` `reset-schema` on `dev`, `test`, `prod` (`confirm` = each name).
2. Restore `sql/` and push; the pipeline rebuilds all three:
   ```powershell
   git clean -fd sql
   git rm -rq sql
   git checkout demo-baseline -- sql
   git commit -m "Reset demo to baseline"
   git push
   ```

## Local sandbox (optional rehearsal)
The Docker stack and the original `run.ps1` commands (`up`, `migrate`, `migrate-all`, `demo-reset`, ...) still work and let you rehearse a scenario without touching the cloud. See PROJECT.md section 4.5.
