@echo off
setlocal
cd /d "%~dp0"

echo ==========================================================
echo   AI Gauge - Instalador Windows (VH2C)
echo ==========================================================
echo.

if not exist "%~dp0windows\install.ps1" goto :NOT_FOUND

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\install.ps1"
goto :END

:NOT_FOUND
echo [ERRO] Nao foi possivel localizar o arquivo windows\install.ps1.
echo Certifique-se de que a pasta foi totalmente extraida do arquivo zip.
echo.

:END
echo.
pause
