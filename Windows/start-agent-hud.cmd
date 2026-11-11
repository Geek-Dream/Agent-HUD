@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-agent-hud.ps1"
if errorlevel 1 (
    echo.
    echo AgentHUD failed to start.
    pause
    exit /b 1
)
endlocal
