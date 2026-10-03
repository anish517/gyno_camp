@echo off
if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

echo ========================================================
echo   GynoCamp - Launch on Real Android Device (RMX3269)
echo   Central Server: http://192.168.16.113:8080 (Wi-Fi) / http://127.0.0.1:8080 (USB)
echo   Cloud OCR: via central server (Gemini key is configured on the SERVER only)
echo ========================================================
echo.
echo 1. Forwarding Port 8080 to phone via USB (if connected)...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080 >nul 2>&1
echo.
echo 2. Launching GynoCamp on your Android Device with live hot-reload...
flutter run -d 1B04293210NA0SCT --dart-define=CENTRAL_SERVER_URL=http://192.168.16.113:8080
pause
