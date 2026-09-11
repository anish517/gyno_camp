@echo off
echo ========================================================
echo   GynoCamp - Direct APK Installer to Real Android Device
echo ========================================================
echo.
echo Installing app-debug.apk directly onto your phone...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-debug.apk
echo.
echo Forwarding server port 8080 over USB...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080
echo.
echo Installation complete! Open GynoCamp on your phone now.
pause
