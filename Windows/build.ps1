param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dotnet = Get-Command dotnet -ErrorAction Stop

Push-Location $root
try {
    & $dotnet.Source restore "$root\AgentHUD.Windows.sln"
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed."
    }

    if (-not $SkipTests) {
        & $dotnet.Source test "$root\tests\AgentHUD.Core.Tests\AgentHUD.Core.Tests.csproj" `
            -c $Configuration
        if ($LASTEXITCODE -ne 0) {
            throw "Core tests failed."
        }
    }

    & $dotnet.Source build "$root\AgentHUD.Windows.sln" `
        -c $Configuration `
        -p:Platform=x64 `
        --no-restore
    if ($LASTEXITCODE -ne 0) {
        throw "Windows build failed."
    }

    $exe = Get-ChildItem "$root\src\AgentHUD.Windows\bin" `
        -Filter AgentHUD.Windows.exe `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\$Configuration\\" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $exe) {
        throw "AgentHUD.Windows.exe was not produced."
    }

    Write-Host ""
    Write-Host "Build complete:" -ForegroundColor Green
    Write-Host $exe.FullName
}
finally {
    Pop-Location
}
