# ==============================================================================
# GynoCamp - Automated PostgreSQL 16 Setup & Reset Script
# Sets master password to 'postgres', creates 'gynocamp_db', and executes schema.
# ==============================================================================

$ErrorActionPreference = "Stop"
$hba = "C:\PostgreSQL\16\data\pg_hba.conf"
$psql = "C:\Program Files\PostgreSQL\16\bin\psql.exe"
$schemaFile = "F:\gyno_camp\gyno_camp\database\postgres_schema.sql"

Write-Host ">>> Step 1/6: Backing up pg_hba.conf..." -ForegroundColor Cyan
Copy-Item $hba "$hba.setup_backup" -Force

Write-Host ">>> Step 2/6: Temporarily enabling local trust authentication..." -ForegroundColor Cyan
$content = Get-Content $hba
$newContent = $content `
    -replace "host\s+all\s+all\s+127\.0\.0\.1/32\s+scram-sha-256", "host    all             all             127.0.0.1/32            trust" `
    -replace "host\s+all\s+all\s+::1/128\s+scram-sha-256", "host    all             all             ::1/128                 trust"
Set-Content $hba -Value $newContent

Write-Host ">>> Step 3/6: Restarting PostgreSQL 16 service..." -ForegroundColor Cyan
Restart-Service postgresql-16 -Force

Write-Host ">>> Step 4/6: Resetting 'postgres' user password to 'postgres'..." -ForegroundColor Cyan
& $psql -U postgres -h 127.0.0.1 -c "ALTER USER postgres WITH PASSWORD 'postgres';"

Write-Host ">>> Step 5/6: Creating 'gynocamp_db' database..." -ForegroundColor Cyan
$dbExists = (& $psql -U postgres -h 127.0.0.1 -t -A -c "SELECT count(*) FROM pg_database WHERE datname='gynocamp_db'").Trim()
if ($dbExists -eq "0") {
    & $psql -U postgres -h 127.0.0.1 -c "CREATE DATABASE gynocamp_db;"
    Write-Host "Database 'gynocamp_db' created successfully." -ForegroundColor Green
} else {
    Write-Host "Database 'gynocamp_db' already exists." -ForegroundColor Yellow
}

Write-Host ">>> Step 6/6: Restoring secure scram-sha-256 authentication..." -ForegroundColor Cyan
$content = Get-Content $hba
$restoredContent = $content `
    -replace "host\s+all\s+all\s+127\.0\.0\.1/32\s+trust", "host    all             all             127.0.0.1/32            scram-sha-256" `
    -replace "host\s+all\s+all\s+::1/128\s+trust", "host    all             all             ::1/128                 scram-sha-256"
Set-Content $hba -Value $restoredContent
Restart-Service postgresql-16 -Force

Write-Host ">>> Step 7: Applying production schema to gynocamp_db..." -ForegroundColor Cyan
$env:PGPASSWORD = "postgres"
& $psql -U postgres -h 127.0.0.1 -d gynocamp_db -f $schemaFile

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host " SUCCESS! PostgreSQL is now ready for GynoCamp:" -ForegroundColor Green
Write-Host " - Host:     localhost" -ForegroundColor White
Write-Host " - Port:     5432" -ForegroundColor White
Write-Host " - Database: gynocamp_db" -ForegroundColor White
Write-Host " - Username: postgres" -ForegroundColor White
Write-Host " - Password: postgres" -ForegroundColor White
Write-Host "========================================================`n" -ForegroundColor Green
Start-Sleep -Seconds 4
