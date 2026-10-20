# Windows / PowerShell Command Reference

Addendum to `flyway-project-spec.md`. On Windows, `make` is usually unavailable, so the command wrapper is `run.ps1` (a PowerShell script in the project root) instead of the Makefile. The Makefile can stay in the repository for Mac/Linux users.

## 1. Allow the script to run

PowerShell blocks scripts by default. Run this once per terminal window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

The `-Scope Process` flag means the change applies only to the current terminal window and disappears when it is closed, so no permanent system setting is changed.

## 2. Command mapping

Whenever the spec or an instruction says `make X`, run `.\run.ps1 X`. Where it says `ENV=test` (or `ENV=prod`), use `-Target test` (or `-Target prod`) instead. The default target is `dev`.

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

## 3. Notes

- `reset` always runs against dev (the only environment where `clean` is enabled).
- `migrate-all` runs dev, then test, then prod, in that order.
- If you use Git Bash instead of PowerShell, a `run.sh` equivalent can be used instead.