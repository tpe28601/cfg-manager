@echo off
chcp 65001 >nul
cd /d "%~dp0"
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agents-Cfg-Manager-Web.ps1" -OpenBrowser
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agents-Cfg-Manager-Web.ps1" %*
)
