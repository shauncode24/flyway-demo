param(
    [Parameter(Position=0)][string]$Command = "help",
    [Parameter(Position=1)][string]$Arg = "",
    [string]$Target = "dev",
    [switch]$Force
)

$ErrorActionPreference = "Continue"
$validStages = "B1", "B2", "C1", "C2", "D", "E1", "E3", "F"

if ($Target -notin "dev", "test", "prod") {
    Write-Host "Unknown target '$Target'. Use dev, test or prod." -ForegroundColor Red
    exit 1
}

# Run a Flyway command against an environment. Returns the exit code; never throws,
# so a failing migration (a deliberate part of the demo) shows Flyway's own message.
function Invoke-Flyway([string]$Env, [string[]]$FlywayArgs) {
    docker compose run --rm flyway "-configFiles=/flyway/conf/$Env.conf" @FlywayArgs | Out-Host
    return $LASTEXITCODE
}

# Run a Flyway command and stop the script if it fails (used inside multi-step commands).
function Invoke-FlywayOrStop([string]$Env, [string[]]$FlywayArgs) {
    $code = Invoke-Flyway $Env $FlywayArgs
    if ($code -ne 0) {
        Write-Host "Flyway '$($FlywayArgs -join ' ')' failed on $Env (exit $code). Stopping." -ForegroundColor Red
        exit $code
    }
}

function Assert-Docker {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker is not running. Start Docker Desktop and try again." -ForegroundColor Red
        exit 1
    }
}

Assert-Docker

switch ($Command) {
    "up"          { docker compose up -d --build --wait postgres dashboard }
    "info"        { exit (Invoke-Flyway $Target @("info")) }
    "validate"    { exit (Invoke-Flyway $Target @("validate")) }
    "migrate"     { exit (Invoke-Flyway $Target @("migrate")) }
    "migrate-ooo" { exit (Invoke-Flyway $Target @("migrate", "-outOfOrder=true")) }
    "repair"      { exit (Invoke-Flyway $Target @("repair")) }
    "baseline"    { exit (Invoke-Flyway $Target @("baseline", "-baselineVersion=8", "-baselineDescription=Legacy database")) }

    # dev, then test, then prod; stops at the first failure so prod is never touched after a bad dev run
    "migrate-all" {
        foreach ($e in "dev", "test", "prod") {
            Write-Host "=== Migrating $e ===" -ForegroundColor Cyan
            Invoke-FlywayOrStop $e @("migrate")
        }
    }

    # info for all three environments in one go
    "status" {
        foreach ($e in "dev", "test", "prod") {
            Write-Host "=== $e ===" -ForegroundColor Cyan
            Invoke-Flyway $e @("info") | Out-Null
        }
    }

    # Compare the migration history of two environments: .\run.ps1 compare test -Target dev
    "compare" {
        $other = if ($Arg) { $Arg } else { "test" }
        if ($other -notin "dev", "test", "prod" -or $other -eq $Target) {
            Write-Host "Usage: .\run.ps1 compare <other-env> [-Target reference-env]  (two different environments)" -ForegroundColor Red
            exit 1
        }
        $q = "SELECT coalesce(version, 'R:' || description) || '  ' || description || '  checksum=' || checksum || '  success=' || success FROM flyway_schema_history WHERE type <> 'SCHEMA' ORDER BY installed_rank;"
        $a = @(docker compose exec -T postgres psql -U admin -d "$($Target)_db" -At -c $q)
        $b = @(docker compose exec -T postgres psql -U admin -d "$($other)_db" -At -c $q)
        $diff = Compare-Object $a $b
        if (-not $diff) {
            Write-Host "$Target and $other have identical migration history ($($a.Count) entries)." -ForegroundColor Green
        } else {
            Write-Host "$Target and $other differ:" -ForegroundColor Yellow
            foreach ($d in $diff) {
                $where = if ($d.SideIndicator -eq "<=") { "only in $Target" } else { "only in $other" }
                Write-Host ("  [{0}] {1}" -f $where, $d.InputObject)
            }
            exit 1
        }
    }

    # Pre-demo checklist
    "doctor" {
        $ok = $true
        $up = docker compose ps -q postgres
        if (-not $up) {
            foreach ($port in 5432, 3000) {
                if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
                    Write-Host "[FAIL] Port $port is already in use" -ForegroundColor Red; $ok = $false
                } else { Write-Host "[ ok ] Port $port is free" -ForegroundColor Green }
            }
        } else { Write-Host "[ ok ] Stack is running" -ForegroundColor Green }
        $dirty = git status --porcelain
        if ($dirty) { Write-Host "[WARN] Uncommitted changes (demo-reset needs sql/ committed):" -ForegroundColor Yellow; $dirty | ForEach-Object { Write-Host "       $_" } }
        else { Write-Host "[ ok ] Git working tree is clean" -ForegroundColor Green }
        foreach ($f in "demo\legacy_schema.sql", "DEMO.md") {
            if (Test-Path $f) { Write-Host "[ ok ] $f present" -ForegroundColor Green } else { Write-Host "[FAIL] $f missing" -ForegroundColor Red; $ok = $false }
        }
        foreach ($st in $validStages) {
            if (-not (Test-Path "demo\$st")) { Write-Host "[FAIL] demo\$st missing" -ForegroundColor Red; $ok = $false }
        }
        if (-not $ok) { exit 1 }
    }

    # Cheat card for a scenario: .\run.ps1 scenario C
    "scenario" {
        # Cloud pipeline flow: stage, commit, push, then read the Actions run graph.
        # "[Actions]" lines are clicks in GitHub: Actions tab, "Manual Flyway operations", Run workflow.
        $push = 'git add sql; git commit -m "<msg>"; git push'
        $cards = @{
            A = @("Checksum mismatch: applied history is protected",
                  'Add-Content sql\V2__create_products.sql "-- harmless comment"', $push, "[Actions] gate green, dev RED at Validate, test/prod skipped",
                  "git revert HEAD --no-edit; git push   # green again",
                  "(or keep the edit: [Actions] manual repair on dev, confirm=dev; re-run; repeat on test and prod)")
            B = @("Wrong migration that succeeded: roll forward",
                  ".\run.ps1 stage B1", $push, "[Actions] all green: the typo (phon) is now in dev, test and prod",
                  ".\run.ps1 stage B2", $push, "[Actions] all green: V10 renames phon to phone")
            C = @("Failed migration: the gate catches it",
                  ".\run.ps1 stage C1", $push, "[Actions] gate RED (rolled back), dev/test/prod skipped",
                  ".\run.ps1 stage C2", $push, "[Actions] all green")
            D = @("Repeatable migration: tracks content, not version",
                  ".\run.ps1 stage D", $push, "[Actions] all green; only the view is re-applied (old row Superseded)",
                  "(with a required reviewer on test/prod the run pauses: environments differ until you approve)")
            E = @("Version conflict and out-of-order",
                  ".\run.ps1 stage E1", $push, "[Actions] gate RED: duplicate version 12",
                  "Rename-Item sql\V12__add_loyalty_tier.sql V13__add_loyalty_tier.sql", $push, "[Actions] all green (V12 and V13)",
                  ".\run.ps1 stage E3", $push, "[Actions] gate green, dev RED at Validate (V12.5 below V13)",
                  "[Actions] manual migrate-out-of-order on dev, then test, then prod",
                  "[Actions] re-run 'Flyway migrations' on main: green")
            F = @("Baselining an existing database",
                  "First reset to baseline (PROJECT.md 8.5) so sql/ holds V1-V8 only. Do NOT push until the last step.",
                  "[Actions] manual on dev: reset-schema (confirm=dev)", "[Actions] manual on dev: load-legacy-schema",
                  "[Actions] manual on dev: migrate   # RED on purpose: non-empty schema, no history",
                  "[Actions] manual on dev: baseline (version 8)", "[Actions] manual on dev: info   # Below Baseline + Baseline row",
                  ".\run.ps1 stage F", $push, "[Actions] all green: dev applies only V9 + view")
        }
        $key = $Arg.ToUpper()
        if (-not $cards.ContainsKey($key)) { Write-Host "Usage: .\run.ps1 scenario <A|B|C|D|E|F>" -ForegroundColor Red; exit 1 }
        Write-Host "Scenario ${key}: $($cards[$key][0])" -ForegroundColor Cyan
        $cards[$key][1..($cards[$key].Count - 1)] | ForEach-Object { Write-Host "  $_" }
    }

    "history" {
        docker compose exec postgres psql -U admin -d "$($Target)_db" -c "SELECT installed_rank, version, description, type, checksum, installed_by, execution_time, success FROM flyway_schema_history ORDER BY installed_rank;"
    }

    "psql"  { docker compose exec postgres psql -U admin -d "$($Target)_db" }

    # dev only: clean is disabled in test and prod
    "reset" {
        Invoke-FlywayOrStop "dev" @("clean")
        Invoke-FlywayOrStop "dev" @("migrate")
    }

    # Copy a prepared demo file set into sql/  (e.g. .\run.ps1 stage B1)
    "stage" {
        if ($Arg -notin $validStages) {
            Write-Host "Unknown stage '$Arg'. Available: $($validStages -join ' ')" -ForegroundColor Red
            exit 1
        }
        Copy-Item "demo\$Arg\*" sql\ -Force
        Write-Host "Staged demo\$Arg into sql\" -ForegroundColor Green
    }

    # Create the legacy (non-Flyway) schema in dev_db for the baseline demo
    "legacy" {
        Get-Content demo\legacy_schema.sql -Raw | docker compose exec -T postgres psql -U admin -d dev_db
    }

    # Back to a clean, fully migrated state: sql/ = committed files, all three DBs migrated
    "demo-reset" {
        $dirty = git status --porcelain -- sql
        $tracked = $dirty | Where-Object { $_ -notmatch '^\?\?' }
        if ($tracked -and -not $Force) {
            Write-Host "Uncommitted changes in sql/ would be lost:" -ForegroundColor Yellow
            $tracked | ForEach-Object { Write-Host "  $_" }
            Write-Host "Commit them first, or run .\run.ps1 demo-reset -Force to discard them." -ForegroundColor Yellow
            exit 1
        }
        # Remove staged scenario files (anything in sql/ not tracked by git), then restore the rest
        git clean -fdq -- sql
        git checkout -- sql
        docker compose down -v
        docker compose up -d --wait postgres dashboard
        foreach ($e in "dev", "test", "prod") {
            Write-Host "=== Migrating $e ===" -ForegroundColor Cyan
            Invoke-FlywayOrStop $e @("migrate")
        }
        Write-Host "Demo reset complete. Dashboard: http://localhost:3000" -ForegroundColor Green
    }

    "down"  { docker compose down -v }

    default {
        Write-Host "Usage: .\run.ps1 <command> [arg] [-Target dev|test|prod]"
        Write-Host "Core:  up, info, validate, migrate, migrate-all, status, compare <env>, history, psql, repair, down"
        Write-Host "Demo:  doctor, scenario <A-F>, stage <$($validStages -join '|')>, migrate-ooo, baseline, legacy, reset, demo-reset"
    }
}
