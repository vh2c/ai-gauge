@echo off
title AI Gauge - Instalador Windows (VH2C)
echo ==========================================================
echo   Iniciando Instalador do AI Gauge...
echo ==========================================================
echo.

if not exist "%~dp0install.ps1" (
    echo [ATENCAO] Os arquivos ainda estao compactados dentro do .zip!
    echo.
    echo Para prosseguir com a instalacao:
    echo  1. Feche esta janela.
    echo  2. Clique com o botao direito no arquivo "AI-Gauge-Windows-vh2c.zip".
    echo  3. Clique em "Extrair Tudo..." (ou Extract All).
    echo  4. Abra a nova pasta extraida e clique duas vezes em "install.bat".
    echo.
    pause
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
