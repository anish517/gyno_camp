@echo off
:: ==============================================================================
:: GynoCamp - Launch Simultaneously on BOTH Android Device & Chrome
:: ==============================================================================
title GynoCamp - Dual Device Runner (Android + Chrome)

if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

echo ==============================================================================
echo   GynoCamp Dual-Device Launcher (Chrome + Android RMX3269)
echo   Central Sync Server : http://192.168.16.113:8080 (Wi-Fi / USB / Localhost)
echo   Cloud OCR: via central server (Gemini key is configured on the SERVER only)
echo ==============================================================================
echo.

echo 1. Forwarding Port 8080 to Android Device via USB (if connected)...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080 >nul 2>&1

echo.
echo 2. Launching GynoCamp on BOTH Chrome and your Android phone...
echo    (Press 'r' in this terminal to hot-reload BOTH devices simultaneously!)
echo.

flutter run -d all --web-port=5000 --dart-define=CENTRAL_SERVER_URL=http://192.168.16.113:8080

pause
