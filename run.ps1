param(
    [Parameter(Position=0)][string]$Command = "help",
    [Parameter(Position=1)][string]$Arg = "",
    [string]$Target = "dev"
)

$fw = @("compose", "run", "--rm", "flyway", "-configFiles=/flyway/conf/$Target.conf")

switch ($Command) {
    "up"       { docker compose up -d --build postgres dashboard }
    "info"     { docker @fw info }
    "validate" { docker @fw validate }
    "migrate"  { docker @fw migrate }
    "migrate-ooo" { docker @fw migrate "-outOfOrder=true" }
    "repair"   { docker @fw repair }
    "baseline" { docker @fw baseline "-baselineVersion=8" "-baselineDescription=Legacy database" }

    "migrate-all" {
        foreach ($e in "dev", "test", "prod") {
            Write-Host "=== Migrating $e ===" -ForegroundColor Cyan
            docker compose run --rm flyway "-configFiles=/flyway/conf/$e.conf" migrate
        }
    }

    "history" {
        docker compose exec postgres psql -U admin -d "$($Target)_db" -c "SELECT installed_rank, version, description, type, checksum, installed_by, execution_time, success FROM flyway_schema_history ORDER BY installed_rank;"
    }

    "psql"  { docker compose exec postgres psql -U admin -d "$($Target)_db" }

    "reset" {
        docker compose run --rm flyway "-configFiles=/flyway/conf/dev.conf" clean
        docker compose run --rm flyway "-configFiles=/flyway/conf/dev.conf" migrate
    }

    # Copy a prepared demo file set into sql/  (e.g. .\run.ps1 stage B1)
    "stage" {
        if (-not (Test-Path "demo\$Arg")) {
            Write-Host "Unknown stage '$Arg'. Available: B1 B2 C1 C2 D E1 E3 F" -ForegroundColor Red
        } else {
            Copy-Item "demo\$Arg\*" sql\ -Force
            Write-Host "Staged demo\$Arg into sql\" -ForegroundColor Green
        }
    }

    # Create the legacy (non-Flyway) schema in dev_db for the baseline demo
    "legacy" {
        Get-Content demo\legacy_schema.sql -Raw | docker compose exec -T postgres psql -U admin -d dev_db
    }

    # Back to a clean, fully migrated state: sql/ = committed files, all three DBs migrated
    "demo-reset" {
        Remove-Item sql\V9__*.sql, sql\V1[0-9]__*.sql, sql\V12_5__*.sql -ErrorAction SilentlyContinue
        git checkout -- sql
        docker compose down -v
        docker compose up -d postgres dashboard
        foreach ($e in "dev", "test", "prod") {
            Write-Host "=== Migrating $e ===" -ForegroundColor Cyan
            docker compose run --rm flyway "-configFiles=/flyway/conf/$e.conf" migrate
        }
        Write-Host "Demo reset complete. Dashboard: http://localhost:3000" -ForegroundColor Green
    }

    "down"  { docker compose down -v }

    default {
        Write-Host "Usage: .\run.ps1 <command> [arg] [-Target dev|test|prod]"
        Write-Host "Core:  up, info, validate, migrate, migrate-all, history, psql, repair, down"
        Write-Host "Demo:  stage <B1|B2|C1|C2|D|E1|E3|F>, migrate-ooo, baseline, legacy, reset, demo-reset"
    }
}
