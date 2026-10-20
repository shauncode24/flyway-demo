param(
    [Parameter(Position=0)][string]$Command = "help",
    [string]$Target = "dev"
)

$fw = @("compose", "run", "--rm", "flyway", "-configFiles=/flyway/conf/$Target.conf")

switch ($Command) {
    "up"       { docker compose up -d --build postgres dashboard }
    "info"     { docker @fw info }
    "validate" { docker @fw validate }
    "migrate"  { docker @fw migrate }
    "repair"   { docker @fw repair }
    "baseline" { docker @fw baseline }

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

    "down"  { docker compose down -v }

    default {
        Write-Host "Usage: .\run.ps1 <command> [-Target dev|test|prod]"
        Write-Host "Commands: up, info, validate, migrate, migrate-all, repair, baseline, history, psql, reset, down"
    }
}