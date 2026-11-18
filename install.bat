@echo off
setlocal
cd /d "%~dp0"

echo ==========================================================
echo   AI Gauge - Windows Installer (VH2C)
echo ==========================================================
echo.

if not exist "%~dp0windows\install.ps1" goto :NOT_FOUND

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\install.ps1"
goto :END

:NOT_FOUND
echo [ERROR] Could not find windows\install.ps1.
echo Make sure the folder was fully extracted from the zip file.
echo.

:END
echo.
pause
