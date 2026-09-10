@echo off
:: ==============================================================================
:: GynoCamp - 1-Click Automated PostgreSQL Setup & Reset (Auto-Elevating)
:: ==============================================================================

:: Check for administrative rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [GynoCamp] Requesting Administrator Elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Running with Administrator Privileges
title GynoCamp - PostgreSQL 16 Automated Setup
echo ========================================================
echo  GynoCamp: Setting up PostgreSQL 16 Database
echo ========================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\scripts\setup_postgres.ps1"

echo.
echo Setup completed! You may close this window.
pause
