@echo off
setlocal
set "ROOT=%~dp0"
set "DOTNET_ROOT=%ROOT%.dotnet"
set "PATH=%ROOT%.dotnet;%PATH%"
start "" "%ROOT%ui-build\x64\Release\net8.0-windows10.0.19041.0\AgentHUD.Windows.exe" --show
