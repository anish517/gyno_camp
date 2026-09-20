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
if defined GEMINI_API_KEY (
    echo  Gemini Flash OCR: Active [OK]
) else (
    echo  Gemini Flash OCR: (Key missing in local_env.bat)
)
echo ========================================================
echo.

flutter run -d chrome --web-port=5000 --web-browser-flag="--user-data-dir=%CD%\.chrome_dev_data" --dart-define=GEMINI_API_KEY=%GEMINI_API_KEY% --dart-define=CENTRAL_SERVER_URL=http://localhost:8080

