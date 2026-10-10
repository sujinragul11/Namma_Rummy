@echo off
rem Writes the Xcode project of the game into build\ios. Apple's tools only run on a Mac:
rem copy that folder to one, open namma-rummy.xcodeproj in Xcode, then Product ^> Archive.
rem Needs your Apple Team ID in godot\export_presets.cfg (application/app_store_team_id).

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-app.ps1" ios
echo.
pause
