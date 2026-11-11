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

function Test-DotnetAvailable {
    if (Test-Path "$root\.dotnet\dotnet.exe") {
        return $true
    }
    $installed = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $installed) {
        return $false
    }
    $runtimes = & $installed.Source --list-runtimes 2>$null
    return ($LASTEXITCODE -eq 0 -and
        ($runtimes -match "Microsoft\.NETCore\.App 8\.") -and
        ($runtimes -match "Microsoft\.AspNetCore\.App 8\."))
}

function Test-BuildCurrent {
    param(
        [System.IO.FileInfo]$Executable
    )

    if ($null -eq $Executable) {
        return $false
    }

    $newestSource = Get-ChildItem "$root\src" -Recurse -File |
        Where-Object {
            $_.FullName -notmatch "\\(bin|obj)\\" -and
            $_.Extension -in ".cs", ".xaml", ".csproj", ".manifest"
        } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    return $null -eq $newestSource -or
        $Executable.LastWriteTimeUtc -ge $newestSource.LastWriteTimeUtc
}

$exe = if ($Rebuild) { $null } else { Find-Executable }
if ($null -eq $exe -or
    -not (Test-DotnetAvailable) -or
    -not (Test-BuildCurrent $exe)) {
    & "$root\build.ps1" -Configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "AgentHUD build failed."
    }
    $exe = Find-Executable
}

if ($null -eq $exe) {
    throw "AgentHUD.Windows.exe was not produced. Run Windows\build.ps1 first."
}

if (Test-Path "$root\.dotnet\dotnet.exe") {
    $env:DOTNET_ROOT = "$root\.dotnet"
    $env:PATH = "$root\.dotnet;$env:PATH"
}

$startupLog = Join-Path $env:LOCALAPPDATA "AgentHUD\startup-error.log"
if (Test-Path $startupLog) {
    Remove-Item $startupLog -Force -ErrorAction SilentlyContinue
}

$process = Start-Process `
    -FilePath $exe.FullName `
    -WorkingDirectory $exe.DirectoryName `
    -PassThru

Start-Sleep -Seconds 4
$process.Refresh()
if ($process.HasExited) {
    if (Test-Path $startupLog) {
        Write-Host ""
        Write-Host "AgentHUD startup error:" -ForegroundColor Red
        Get-Content $startupLog -Tail 40
        Write-Host ""
        Write-Host "Full log: $startupLog"
    }
    throw ("AgentHUD exited during startup. Exit code: 0x{0:X8}." -f $process.ExitCode)
}
