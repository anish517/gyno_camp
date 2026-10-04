@echo off
if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

:: ── Auto-detect current Wi-Fi IP address ──────────────────────────────────
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /C:"IPv4 Address"') do (
    set RAW_IP=%%a
    goto :found_ip
)
:found_ip
:: Strip leading space from the IP
set LOCAL_IP=%RAW_IP: =%

echo ========================================================
echo   GynoCamp - Real Device Launcher
echo   Detected IP : http://%LOCAL_IP%:8080  (Wi-Fi)
echo   USB Fallback: http://127.0.0.1:8080   (adb reverse)
echo ========================================================
echo.

echo [1/3] Setting up ADB port-forward (USB cable mode)...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080 >nul 2>&1
echo       Done (ignored if no USB device connected)
echo.

echo [2/3] Choose launch target:
echo   A = Android device  (Wi-Fi IP: %LOCAL_IP%)
echo   B = Opera / Chrome  (Web on port 5000, server at %LOCAL_IP%)
echo   Q = Quit
echo.
set /p CHOICE="Enter A / B / Q: "

if /I "%CHOICE%"=="A" goto :android
if /I "%CHOICE%"=="B" goto :web
if /I "%CHOICE%"=="Q" goto :end
echo Invalid choice. Defaulting to Android...

:android
echo.
echo [3/3] Launching on Android device...
flutter run -d 1B04293210NA0SCT --dart-define=CENTRAL_SERVER_URL=http://%LOCAL_IP%:8080
goto :end

:web
echo.
echo [3/3] Launching Web (Chrome/Opera) with Wi-Fi server URL...
echo       Open in Opera: http://localhost:5000
flutter run -d chrome --web-port=5000 --dart-define=CENTRAL_SERVER_URL=http://%LOCAL_IP%:8080
goto :end

:end
pause
