@echo off
if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

echo ========================================================
echo   GynoCamp - Launch on Real Android Device (RMX3269)
echo   Central Server: http://192.168.110.108:8080
if defined GEMINI_API_KEY (
    echo   Gemini API Key: Configured [OK]
) else (
    echo   Gemini API Key: (Not set - enter in local_env.bat)
)
echo ========================================================
echo.
echo 1. Forwarding Port 8080 to phone via USB...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080
echo.
echo 2. Launching GynoCamp on your Android Device with live hot-reload...
flutter run -d 1B04293210NA0SCT --dart-define=CENTRAL_SERVER_URL=http://192.168.110.108:8080 --dart-define=GEMINI_API_KEY=%GEMINI_API_KEY%
pause
