@echo off
rem Puts the game server on your own Linux machine (a DigitalOcean droplet, for example)
rem with HTTPS, and updates it on later runs:
rem   deploy-server.bat root@203.0.113.10 rummy.example.com
rem The first argument is the ssh address of the machine, the second the public name the
rem apps connect to (its DNS record must point at the machine). Details in deploy-server.ps1.

if "%~2"=="" (
  echo Use: deploy-server.bat ^<user@server-ip^> ^<host name^>
  echo   for example: deploy-server.bat root@203.0.113.10 rummy.example.com
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-server.ps1" -Server "%~1" -HostName "%~2"
echo.
pause
