@echo off
echo ========================================================
echo   GynoCamp Android Emulator Launcher
echo ========================================================
echo.
echo Launching Pixel 6 Android Emulator...
start "" flutter emulators --launch Pixel_6_API_33
echo.
echo Waiting 10 seconds for emulator to start...
timeout /t 10 /nobreak >nul
echo.
echo Starting GynoCamp on Android with hot-reload...
flutter run -d android
pause
