@echo off
if exist "%~dp0local_env.bat" call "%~dp0local_env.bat"

echo ========================================================
echo   GynoCamp Android APK Builder (Debug & Release)
echo   Target Server: http://192.168.16.113:8080
if defined GEMINI_API_KEY (
    echo   Gemini API Key: Configured [OK]
) else (
    echo   Gemini API Key: (Not set - enter in local_env.bat)
)
echo ========================================================
echo.
echo Select build type:
echo [1] Debug APK   (Fastest, for testing on local phone/tablet)
echo [2] Release APK (Optimized, for production/deployment)
echo.
set /p choice="Enter choice (1 or 2): "

if "%choice%"=="2" (
    echo.
    echo Building Production Release APK (Target Server: http://192.168.16.113:8080)...
    flutter build apk --release --dart-define=CENTRAL_SERVER_URL=http://192.168.16.113:8080 --dart-define=GEMINI_API_KEY=%GEMINI_API_KEY%
    echo.
    echo APK Output Location:
    echo   build\app\outputs\flutter-apk\app-release.apk
) else (
    echo.
    echo Building Debug APK (Target Server: http://192.168.16.113:8080)...
    flutter build apk --debug --dart-define=CENTRAL_SERVER_URL=http://192.168.16.113:8080 --dart-define=GEMINI_API_KEY=%GEMINI_API_KEY%
    echo.
    echo APK Output Location:
    echo   build\app\outputs\flutter-apk\app-debug.apk
)

echo.
pause
