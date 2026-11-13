@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "TB_ACTIVE_TOOL="
for /f "delims=" %%I in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Standalone-Update.ps1" -Action Resolve') do set "TB_ACTIVE_TOOL=%%I"
if defined TB_ACTIVE_TOOL (
    call "%TB_ACTIVE_TOOL%\Run-Agents-Cfg-Manager-Web.bat" %*
    exit /b
)
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agents-Cfg-Manager-Web.ps1" -OpenBrowser
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Agents-Cfg-Manager-Web.ps1" %*
)
