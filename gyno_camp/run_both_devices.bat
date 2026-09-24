@echo off
:: ==============================================================================
:: GynoCamp - Launch Simultaneously on BOTH Android Device & Chrome
:: ==============================================================================
title GynoCamp - Dual Device Runner (Android + Chrome)

if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

echo ==============================================================================
echo   GynoCamp Dual-Device Launcher (Chrome + Android RMX3269)
echo   Central Sync Server : http://192.168.1.4:8080 (Wi-Fi / USB / Localhost)
if defined GEMINI_API_KEY (
    echo   Gemini Flash OCR    : Active [OK]
) else (
    echo   Gemini Flash OCR    : (Key missing in local_env.bat)
)
echo ==============================================================================
echo.

echo 1. Forwarding Port 8080 to Android Device via USB (if connected)...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080 >nul 2>&1

echo.
echo 2. Launching GynoCamp on BOTH Chrome and your Android phone...
echo    (Press 'r' in this terminal to hot-reload BOTH devices simultaneously!)
echo.

flutter run -d all --web-port=5000 --dart-define=CENTRAL_SERVER_URL=http://192.168.1.4:8080 --dart-define=GEMINI_API_KEY=%GEMINI_API_KEY%

pause
