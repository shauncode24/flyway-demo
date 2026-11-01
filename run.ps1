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
        Write-Host "Core:  up, info, validate, migrate, migrate-all, status, history, psql, repair, down"
        Write-Host "Demo:  stage <$($validStages -join '|')>, migrate-ooo, baseline, legacy, reset, demo-reset"
    }
}
