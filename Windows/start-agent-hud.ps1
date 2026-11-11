param(
    [switch]$Rebuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Executable {
    Get-ChildItem "$root\src\AgentHUD.Windows\bin" `
        -Filter AgentHUD.Windows.exe `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\Release\\" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

$exe = if ($Rebuild) { $null } else { Find-Executable }
if ($null -eq $exe) {
    & "$root\build.ps1" -Configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "AgentHUD build failed."
    }
    $exe = Find-Executable
}

if ($null -eq $exe) {
    throw "找不到 AgentHUD.Windows.exe。请先运行 Windows\build.ps1。"
}

Start-Process -FilePath $exe.FullName
