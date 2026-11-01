# Windows / PowerShell Command Reference

Addendum to `PROJECT.md`. On Windows, `make` is usually unavailable, so the command wrapper is `run.ps1` (a PowerShell script in the project root) instead of the Makefile. The Makefile can stay in the repository for Mac/Linux users.

**Scope.** The main workflow of this project runs in GitHub Actions: stage a file, commit, push, and read the Actions tab (see `DEMO.md`). `run.ps1` is used for two things: the helper commands in section 1 (needed for the pipeline demo) and the local Docker sandbox commands in section 3 (optional rehearsal, not the cloud).

## 0. Allow the script to run

PowerShell blocks scripts by default. Run this once per terminal window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

The `-Scope Process` flag means the change applies only to the current terminal window and disappears when it is closed, so no permanent system setting is changed.

## 1. Commands used with the pipeline

| Command | What it does |
|---|---|
| `.\run.ps1 stage <B1 B2 C1 C2 D E1 E3 F>` | Copies a prepared scenario file set from `demo/<name>/` into `sql/`. Then commit and push to send it to the pipeline. |
| `.\run.ps1 scenario <A-F>` | Prints the steps for a scenario (local commands, git commands, and the manual-workflow clicks marked `[Actions]`). |
| `.\run.ps1 doctor` | Pre-demo checklist: git tree, demo files, local ports. |

Typical scenario step:

```powershell
.\run.ps1 stage C1
git add sql; git commit -m "Add loyalty points"; git push
```

Manual operations (repair, baseline, out-of-order, reset) are not PowerShell commands: use GitHub, Actions tab, **Manual Flyway operations**, Run workflow.

## 2. Resetting the cloud demo

Applied migrations stay applied. To start again: run `reset-schema` in the manual workflow for `dev`, `test` and `prod`, then restore `sql/` from the baseline tag and push:

```powershell
git clean -fd sql
git rm -rq sql
git checkout demo-baseline -- sql
git commit -m "Reset demo to baseline"
git push
```

## 3. Local sandbox commands (optional)

These run against the local Docker Postgres (`dev_db`, `test_db`, `prod_db`), not the cloud. Whenever an instruction says `make X`, run `.\run.ps1 X`. Where it says `ENV=test` (or `ENV=prod`), use `-Target test` (or `-Target prod`) instead. The default target is `dev`.

| Makefile | PowerShell |
|---|---|
| `make up` | `.\run.ps1 up` |
| `make info` | `.\run.ps1 info` |
| `make info ENV=prod` | `.\run.ps1 info -Target prod` |
| `make validate` | `.\run.ps1 validate` |
| `make migrate` | `.\run.ps1 migrate` |
| `make migrate ENV=test` | `.\run.ps1 migrate -Target test` |
| `make migrate-all` | `.\run.ps1 migrate-all` |
| `make repair` | `.\run.ps1 repair` |
| `make baseline` | `.\run.ps1 baseline` |
| `make history` | `.\run.ps1 history` |
| `make history ENV=prod` | `.\run.ps1 history -Target prod` |
| `make psql` | `.\run.ps1 psql` |
| `make reset` | `.\run.ps1 reset` |
| `make down` | `.\run.ps1 down` |

Notes:

- `reset` always runs against dev (the only local environment where `clean` is enabled).
- `migrate-all` runs dev, then test, then prod, in that order.
- `demo-reset` returns the **local** stack to a clean, migrated state; it does not touch the cloud.
- If you use Git Bash instead of PowerShell, a `run.sh` equivalent can be used instead.
