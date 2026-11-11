param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$localDotnetRoot = Join-Path $root ".dotnet"
$localDotnet = Join-Path $localDotnetRoot "dotnet.exe"

function Resolve-Dotnet {
    if (Test-Path $localDotnet) {
        return $localDotnet
    }

    $installed = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $installed) {
        $versionText = & $installed.Source --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $versionText) {
            $major = [int](($versionText -split "\.")[0])
            if ($major -eq 8) {
                return $installed.Source
            }
        }
    }

    Write-Host "Installing .NET 8 SDK into Windows\.dotnet..." -ForegroundColor Yellow
    Write-Host "This first-time setup needs an internet connection."

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $installer = Join-Path $env:TEMP "agent-hud-dotnet-install.ps1"
    try {
        Invoke-WebRequest `
            -UseBasicParsing `
            -Uri "https://dot.net/v1/dotnet-install.ps1" `
            -OutFile $installer
        & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $installer `
            -Channel 8.0 `
            -InstallDir $localDotnetRoot `
            -NoPath
        if ($LASTEXITCODE -ne 0) {
            throw ".NET SDK installer failed."
        }
    }
    catch {
        throw "Unable to install .NET 8 SDK automatically. $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $installer) {
            Remove-Item $installer -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path $localDotnet)) {
        throw ".NET 8 SDK installation did not produce dotnet.exe."
    }
    return $localDotnet
}

$dotnetPath = Resolve-Dotnet
$dotnetRoot = Split-Path -Parent $dotnetPath
$env:DOTNET_ROOT = $dotnetRoot
$env:PATH = "$dotnetRoot;$env:PATH"

Push-Location $root
try {
    & $dotnetPath restore "$root\AgentHUD.Windows.sln"
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed."
    }

    if (-not $SkipTests) {
        & $dotnetPath test "$root\tests\AgentHUD.Core.Tests\AgentHUD.Core.Tests.csproj" `
            -c $Configuration
        if ($LASTEXITCODE -ne 0) {
            throw "Core tests failed."
        }
    }

    & $dotnetPath build "$root\AgentHUD.Windows.sln" `
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
