@echo off
rem Signs an Android App Bundle with your upload key so Google Play accepts it:
rem   sign-android.bat      turns build\namma-rummy-<version>-<code>-unsigned.aab
rem                         into build\namma-rummy-<version>-<code>.aab
rem For a bundle that was built without the key, for example by a helper that could not ask
rem for your password. build-android.bat asks for the password and signs by itself.
rem The paths are the same as at the top of build-app.ps1.
setlocal
set "JDK=%LOCALAPPDATA%\Android\jdk-17"
set "KEY=%USERPROFILE%\namma-rummy-keys\upload-key.jks"
set "BUILD=%~dp0build"

if not exist "%JDK%\bin\jarsigner.exe" (
    echo JDK 17 was not found at %JDK%
    goto :end
)
if not exist "%KEY%" (
    echo No upload key at %KEY%
    echo Run build-android.bat once: it creates the key and signs the bundle itself.
    goto :end
)
set "IN="
for %%f in ("%BUILD%\namma-rummy-*-unsigned.aab") do set "IN=%%~ff"
if not defined IN (
    echo No unsigned bundle found in %BUILD%
    goto :end
)
set "OUT=%IN:-unsigned.aab=.aab%"

echo Signing %IN%
echo Type the password of your upload key when asked. Nothing shows while you type.
echo.
"%JDK%\bin\jarsigner.exe" -keystore "%KEY%" -signedjar "%OUT%" "%IN%" upload
if errorlevel 1 (
    echo.
    echo Signing failed. Nothing was changed.
    goto :end
)
"%JDK%\bin\jarsigner.exe" -verify "%OUT%" | findstr /C:"jar verified" >nul
if errorlevel 1 (
    echo.
    echo The signed file did not verify. Do not upload it.
    goto :end
)
echo.
echo Done. Upload to Google Play: %OUT%

:end
echo.
pause
