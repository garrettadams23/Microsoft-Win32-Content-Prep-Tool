@echo off
rem Packages every app folder in input\ into a .intunewin file in output\.
rem Double-click it, or run it from a terminal (arguments go to Build-IntuneWin.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-IntuneWin.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
pause
exit /b %EXIT_CODE%
