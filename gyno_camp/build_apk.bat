@echo off
echo ========================================================
echo   GynoCamp Android APK Builder (Debug & Release)
echo ========================================================
echo.
echo Select build type:
echo [1] Debug APK   (Fastest, for testing on local phone/tablet)
echo [2] Release APK (Optimized, for production/deployment)
echo.
set /p choice="Enter choice (1 or 2): "

if "%choice%"=="2" (
    echo.
    echo Building Production Release APK...
    flutter build apk --release
    echo.
    echo APK Output Location:
    echo   build\app\outputs\flutter-apk\app-release.apk
) else (
    echo.
    echo Building Debug APK...
    flutter build apk --debug
    echo.
    echo APK Output Location:
    echo   build\app\outputs\flutter-apk\app-debug.apk
)

echo.
pause
