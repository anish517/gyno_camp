@echo off
:: ==============================================================================
:: GynoCamp - Central Cloud Synchronization API Server Launcher
:: ==============================================================================
title GynoCamp - Central Cloud Sync API Server
echo ==============================================================================
echo  GynoCamp Central Cloud Synchronization REST API (Port 8080)
echo  Bridges Central PostgreSQL with Web (Chrome/Opera) and Android Tablets
echo ==============================================================================
echo.

if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

set PORT=8080
set PGHOST=localhost
set PGPORT=5432
set PGDATABASE=gynocamp_db
set PGUSER=postgres
set PGPASSWORD=postgres

if defined GEMINI_API_KEY (
    echo Cloud OCR (Gemini): server key configured [OK]
) else (
    echo Cloud OCR (Gemini): GEMINI_API_KEY not set - apps will fall back to offline OCR
)
echo Target PostgreSQL: %PGUSER%@%PGHOST%:%PGPORT%/%PGDATABASE%
echo Starting Dart Server...
echo.

dart run bin/server.dart

pause
