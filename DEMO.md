# Live Demo Runbook

Every step is a command. Keep the dashboard (http://localhost:3000) open next to the terminal.

## Before the audience arrives
1. Everything is committed (`git status` is clean). `demo-reset` relies on this.
2. Run Docker Desktop and then:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\run.ps1 demo-reset
   ```
3. Dashboard shows dev, test and prod all **In sync**, 9 applied, 0 pending.
   Use `.\run.ps1 demo-reset -Force` to discard uncommitted edits in `sql/` (e.g. a leftover Scenario A edit).
4. Do one complete dry run of this whole document at least once beforehand.

Return to a clean state at any point with `.\run.ps1 demo-reset`.

---

## Part 1: Create, apply, track
```powershell
.\run.ps1 down
.\run.ps1 up
.\run.ps1 info              # all Pending
.\run.ps1 migrate           # applies V1-V8 and the view to dev
.\run.ps1 info              # all Success
.\run.ps1 history           # flyway_schema_history table
.\run.ps1 migrate-all       # test and prod get the same schema
```
Dashboard: dev In sync, test and prod move from Not initialised to In sync.

## Scenario A: checksum mismatch
```powershell
.\run.ps1 validate                                            # passes
Add-Content sql\V2__create_products.sql "-- harmless comment"
.\run.ps1 validate                                            # FAILS: checksum mismatch
.\run.ps1 migrate                                             # refuses to run too
git checkout sql/V2__create_products.sql
.\run.ps1 validate                                            # passes again
```
Optional repair demo: make the edit again, run `.\run.ps1 repair`, `.\run.ps1 history` (new checksum),
then restore with `git checkout sql/V2__create_products.sql` and `.\run.ps1 repair`.

## Scenario B: wrong migration, roll forward
```powershell
.\run.ps1 stage B1          # V9 with a typo: column "phon"
.\run.ps1 migrate           # succeeds, the SQL is valid
.\run.ps1 history
.\run.ps1 stage B2          # V10 renames phon to phone
.\run.ps1 migrate
.\run.ps1 psql              # then: \d customers   and   \q
```
Point out: V9 is never edited. History is append-only; Community edition has no undo.

## Scenario C: failed migration
```powershell
.\run.ps1 stage C1          # V11 with a syntax error
.\run.ps1 migrate           # FAILS
.\run.ps1 info              # V11 still Pending: PostgreSQL rolled the DDL back
.\run.ps1 stage C2          # overwrites V11 with the corrected file
.\run.ps1 migrate           # succeeds
```

## Scenario D: repeatable migration
Scenarios B and C were applied to dev only. Bring test and prod level first so the only
difference left on the dashboard is the one this scenario creates:
```powershell
.\run.ps1 migrate-all      # dev, test and prod all at the same version again
.\run.ps1 stage D           # view gets a new column
.\run.ps1 migrate           # only the repeatable migration is re-applied
.\run.ps1 history
```
Dashboard: the view row shows "differs" for test and prod. Then bring them level:
```powershell
.\run.ps1 migrate-all
```

## Scenario E: version conflict and out-of-order
```powershell
.\run.ps1 stage E1          # two files both numbered V12
.\run.ps1 migrate           # FAILS: more than one migration with version 12
Rename-Item sql\V12__add_loyalty_tier.sql V13__add_loyalty_tier.sql
.\run.ps1 migrate           # applies V12 and V13
.\run.ps1 stage E3          # V12.5: lower than the already-applied V13
.\run.ps1 migrate           # FAILS validation: resolved migration not applied
.\run.ps1 migrate-ooo       # outOfOrder=true applies it
.\run.ps1 info
```

## Scenario F: baselining an existing database
```powershell
.\run.ps1 demo-reset
.\run.ps1 down
.\run.ps1 up
.\run.ps1 legacy            # builds a hand-made schema in dev_db
.\run.ps1 psql              # then: \dt   and   \q   (tables exist, no Flyway history)
.\run.ps1 migrate           # optional: FAILS, non-empty schema without history
.\run.ps1 baseline          # marks the database as version 8
.\run.ps1 info              # V1-V8 show "Below Baseline"; the dashboard shows them as Baselined
.\run.ps1 stage F           # V9 adds customers.phone
.\run.ps1 migrate           # only V9 and the view are applied
```

## CI demo (prepare in advance)
```powershell
.\run.ps1 demo-reset
git checkout -b broken-migration
.\run.ps1 stage C1
git add .
git commit -m "Add broken migration"
git push -u origin broken-migration     # GitHub Actions run turns red
git checkout main                       # broken file disappears with the branch
```
Show the red run, then a green run on `main`.

## Finish
```powershell
.\run.ps1 demo-reset
```
