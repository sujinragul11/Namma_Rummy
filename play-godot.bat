@echo off
rem Opens the Godot game in two windows, one per player, so a whole game can be played on
rem this PC: player 1 on the left, player 2 on the right. Each window keeps its own login.
rem Starts the backend first if it is not running yet.
rem
rem If Godot is somewhere else on your PC, change the next line.
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

cd /d "%~dp0"

if not exist "%GODOT%" (
  echo Godot was not found here:
  echo   %GODOT%
  echo Open play-godot.bat in a text editor and correct the GODOT line.
  pause
  exit /b 1
)

netstat -ano | findstr LISTENING | findstr /c:":3001 " >nul
if errorlevel 1 (
  echo Starting the backend in a new window...
  start "Rummy backend" cmd /k "cd /d backend && npm start"
  rem Give it a few seconds to come up
  ping -n 6 127.0.0.1 >nul
) else (
  echo Backend is already running.
)

echo Opening two game windows: player 1 on the left, player 2 on the right.
start "" "%GODOT%" --path godot --side=left
start "" "%GODOT%" --path godot --profile=two --side=right
exit /b 0
