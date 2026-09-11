@echo off
echo ========================================================
echo   GynoCamp - Launch on Real Android Device (RMX3269)
echo ========================================================
echo.
echo 1. Forwarding Port 8080 to phone via USB...
"C:\Users\AnishTiwari\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080
echo.
echo 2. Launching GynoCamp on your Android Device with live hot-reload...
flutter run -d 1B04293210NA0SCT
pause
