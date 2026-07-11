# test_exe_smoke.ps1 - Launch the built EXE under a Restricted execution policy
# and assert it survives startup (embedded helper loading + Docker check).
#
# This exists because the Pester/bash suites test the SCRIPTS, never the
# compiled artifact: the v1.4.0 "running scripts is disabled on this system"
# launcher bug shipped precisely because nothing ever ran the EXE on a machine
# with the Windows default execution policy. Windows only.
#
# Success is defined by log markers that appear only AFTER Test-DockerRunning
# has returned - i.e. after the embedded helper modules loaded and DockerOk
# executed, the exact code path the execution-policy bug broke:
#   - "Docker Desktop is not running"    (no Docker daemon: warning path)
#   - "Performing startup update check"  (Docker present: fully past the check)
#
# Exit codes: 0 = startup marker reached, 1 = failure signature/crash/timeout.
param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,

    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ExePath)) {
    Write-Host "[FAIL] EXE not found: $ExePath" -ForegroundColor Red
    exit 1
}

$logFile = Join-Path $env:LOCALAPPDATA 'AI-Docker-CLI\logs\ai-docker.log'

$successPatterns = @(
    'Docker Desktop is not running',
    'Performing startup update check'
)
$failurePatterns = @(
    'running scripts is disabled',
    'is not recognized as the name of a cmdlet'
)

# The whole point of this test: the EXE must work under the Windows DEFAULT
# policy. The EXE's ps2exe host reads the Windows PowerShell policy, so it is
# set via powershell.exe (a pwsh-side Set-ExecutionPolicy would not apply).
$previousPolicy = (& powershell.exe -NoProfile -Command 'Get-ExecutionPolicy -Scope CurrentUser').Trim()
& powershell.exe -NoProfile -Command 'Set-ExecutionPolicy Restricted -Scope CurrentUser -Force' | Out-Null
Write-Host "[INFO] CurrentUser Windows PowerShell execution policy set to Restricted (was: $previousPolicy)"

if (Test-Path $logFile) { Remove-Item $logFile -Force }

$process = $null
$status = 'timeout'
$matched = ''
try {
    Write-Host "[INFO] Launching $ExePath (timeout ${TimeoutSeconds}s)..."
    $process = Start-Process -FilePath $ExePath -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2

        $log = ''
        if (Test-Path $logFile) {
            $log = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
        }

        if ($log) {
            $failureHit = $failurePatterns | Where-Object { $log -match [regex]::Escape($_) } | Select-Object -First 1
            if ($failureHit) {
                $status = 'failure-signature'
                $matched = $failureHit
                break
            }
            $successHit = $successPatterns | Where-Object { $log -match [regex]::Escape($_) } | Select-Object -First 1
            if ($successHit) {
                $status = 'ok'
                $matched = $successHit
                break
            }
        }

        # A GUI EXE that exits this early crashed (unhandled startup error).
        # Grace-read the log once more on the next loop before concluding.
        if ($process.HasExited) {
            Start-Sleep -Seconds 2
            $log = if (Test-Path $logFile) { Get-Content $logFile -Raw -ErrorAction SilentlyContinue } else { '' }
            $successHit = $successPatterns | Where-Object { $log -and ($log -match [regex]::Escape($_)) } | Select-Object -First 1
            if ($successHit) {
                $status = 'ok'
                $matched = $successHit
            } else {
                $status = 'exited'
            }
            break
        }
    }
} finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    & powershell.exe -NoProfile -Command "Set-ExecutionPolicy $previousPolicy -Scope CurrentUser -Force" | Out-Null
    Write-Host "[INFO] CurrentUser execution policy restored to $previousPolicy"
}

Write-Host ''
Write-Host '--- startup log ---'
if (Test-Path $logFile) {
    Get-Content $logFile -ErrorAction SilentlyContinue | Select-Object -Last 40 | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host '  (no log file was created)'
}
Write-Host '-------------------'
Write-Host ''

switch ($status) {
    'ok' {
        Write-Host "[PASS] EXE started under Restricted policy and reached startup marker: '$matched'" -ForegroundColor Green
        exit 0
    }
    'failure-signature' {
        Write-Host "[FAIL] Startup log contains failure signature: '$matched'" -ForegroundColor Red
        exit 1
    }
    'exited' {
        Write-Host '[FAIL] EXE exited during startup before reaching a success marker (crash?)' -ForegroundColor Red
        exit 1
    }
    default {
        Write-Host "[FAIL] No startup marker within ${TimeoutSeconds}s - the EXE is stuck or startup broke silently" -ForegroundColor Red
        exit 1
    }
}
