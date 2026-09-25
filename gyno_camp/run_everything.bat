@echo off
:: ==============================================================================
:: GynoCamp - Master Full-Stack Launcher (API Server + Web + Android)
:: ==============================================================================
title GynoCamp Master Launcher

if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

echo ==============================================================================
echo   GynoCamp Full-Stack Launcher
echo   1. Central Sync API Server  : http://192.168.16.113:8080 (PostgreSQL gynocamp_db)
echo   2. Chrome Web Application   : http://localhost:5000
echo   3. Android Mobile Device    : RMX3269
echo ==============================================================================
echo.

echo [1/3] Starting Central Cloud Sync API Server in background window...
start "GynoCamp Sync Server" cmd /k "%~dp0start_sync_server.bat"

echo.
echo [2/3] Configuring ADB USB bridge (if phone connected via USB)...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080 >nul 2>&1

echo.
echo [3/3] Launching GynoCamp on BOTH Chrome and your Android Phone...
echo      (Press 'r' in this terminal to hot-reload both devices simultaneously!)
echo.

flutter run -d all --web-port=5000 --dart-define=CENTRAL_SERVER_URL=http://192.168.16.113:8080 --dart-define=GEMINI_API_KEY=%GEMINI_API_KEY%

pause
