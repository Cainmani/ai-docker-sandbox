# docker_helpers.ps1 - Shared Docker detection utilities for AI Docker CLI Manager
# Provides Docker executable discovery and daemon health checks.
# Usage: . "$PSScriptRoot\docker_helpers.ps1"
# NOTE: These functions are Windows-only (use Windows paths and -WindowStyle Hidden).
# DEPENDENCY: Requires log_utils.ps1 to be loaded first (for Write-AppLog).

function Find-Docker() {
    Write-AppLog "Finding Docker executable..." "DEBUG"
    # Check if docker is in PATH
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCmd) {
        Write-AppLog "Docker found in PATH: $($dockerCmd.Source)" "DEBUG"
        return $dockerCmd.Source
    }

    # Check common Docker Desktop installation paths
    $possiblePaths = @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe",
        "$env:ProgramW6432\Docker\Docker\resources\bin\docker.exe"
    )

    Write-AppLog "Docker not in PATH, checking common installation paths..." "DEBUG"
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-AppLog "Docker found at: $path" "DEBUG"
            return $path
        }
    }

    Write-AppLog "Docker executable not found" "WARN"
    return $null
}

function DockerOk() {
    Write-AppLog "Checking if Docker is running..." "DEBUG"
    try {
        $dockerPath = Find-Docker
        if (-not $dockerPath) {
            Write-AppLog "Docker executable not found - Docker is not running" "WARN"
            return $false
        }
        $p = Start-Process -FilePath $dockerPath -ArgumentList "info" -WindowStyle Hidden -PassThru -Wait
        if ($p.ExitCode -eq 0) {
            Write-AppLog "Docker is running and responding" "DEBUG"
            return $true
        } else {
            Write-AppLog "Docker executable found but not running (exit code: $($p.ExitCode))" "WARN"
            return $false
        }
    } catch {
        Write-AppLog "Error checking Docker status: $($_.Exception.Message)" "ERROR"
        return $false
    }
}
