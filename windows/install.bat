@echo off
title AI Gauge - Instalador Windows (VH2C)
echo ==========================================================
echo   Iniciando Instalador do AI Gauge...
echo ==========================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
