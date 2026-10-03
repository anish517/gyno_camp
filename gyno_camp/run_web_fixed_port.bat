@echo off
:: ==============================================================================
:: GynoCamp - Launch Web on Fixed Port 5000 with Persistent Browser Storage & Gemini
:: ==============================================================================
if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

title GynoCamp Web (Fixed Port 5000)
echo ========================================================
echo  Launching GynoCamp Web in Debug Mode
echo  PC Browser URL: http://localhost:5000
echo  Persistent storage directory: %CD%\.chrome_dev_data
echo   Cloud OCR: via central server (Gemini key is configured on the SERVER only)
echo ========================================================
echo.

flutter run -d chrome --web-port=5000 --web-browser-flag="--user-data-dir=%CD%\.chrome_dev_data" --dart-define=CENTRAL_SERVER_URL=http://localhost:8080

