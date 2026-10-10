@echo off
rem Starts the game server and the Expo dev server, each in its own window.
rem Safe to run again: a server that is already running is left alone.
rem   backend -> port 3001   (folder: backend, command: npm start)
rem   Expo    -> port 8081   (folder: mobile,  command: npx expo start)
cd /d "%~dp0"

netstat -ano | findstr LISTENING | findstr /c:":3001 " >nul
if errorlevel 1 (
  echo Starting the backend in a new window...
  start "Rummy backend" cmd /k "cd /d backend && npm start"
) else (
  echo Backend is already running on port 3001.
)

rem Expo moves to 8082 when 8081 is taken, so either port means it is running
netstat -ano | findstr LISTENING | findstr /c:":8081 " /c:":8082 " >nul
if errorlevel 1 (
  echo Starting Expo in a new window. Scan the QR code it prints.
  start "Rummy Expo" cmd /k "cd /d mobile && npx expo start --port 8081"
) else (
  echo Expo is already running. Scan the QR code in its window.
)

rem Keep this window open long enough to read the lines above
timeout /t 6 >nul 2>&1
exit /b 0
