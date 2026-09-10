@echo off
:: ==============================================================================
:: GynoCamp - Launch Web on Fixed Port 5000 with Persistent Browser Storage
:: ==============================================================================
title GynoCamp Web (Fixed Port 5000)
echo ========================================================
echo  Launching GynoCamp Web in Debug Mode
echo  PC Browser URL: http://localhost:5000
echo  Mobile / Real Device URL: http://192.168.1.4:5000
echo  Persistent storage directory: %CD%\.chrome_dev_data
echo ========================================================
echo.

flutter run -d chrome --web-port=5000 --web-browser-flag="--user-data-dir=%CD%\.chrome_dev_data"

