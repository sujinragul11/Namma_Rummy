@echo off
rem Builds the Android files of the game into the build folder:
rem   build-android.bat          the .aab for Google Play and an .apk to try on a phone
rem   build-android.bat bump     the same, with the version code raised by one (every new upload needs that)
rem   build-android.bat debug    a test .apk that plays against the backend on your PC
rem The paths of Godot, Java and the Android SDK are at the top of build-app.ps1.

set "MODE=%~1"
if "%MODE%"=="" set "MODE=release"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-app.ps1" android %MODE%
echo.
pause
