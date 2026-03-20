# env_utils.ps1 - Shared .env file parsing utilities for AI Docker CLI Manager
# Provides .env file reading and variable extraction.
# Usage: . "$PSScriptRoot\env_utils.ps1"

function Read-EnvFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = @{}

    if (-not (Test-Path $Path)) {
        return $result
    }

    $lines = Get-Content $Path
    foreach ($line in $lines) {
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith('#')) { continue }

        # Parse KEY=VALUE
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $result[$Matches[1]] = $Matches[2]
        }
    }

    return $result
}

function Get-EnvVar {
    param(
        [Parameter(Mandatory)]
        [hashtable]$EnvData,

        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Default = $null,

        [string]$ValidationPattern = $null
    )

    $value = if ($EnvData.ContainsKey($Name)) { $EnvData[$Name] } else { $Default }

    if ([string]::IsNullOrEmpty($value) -and -not $EnvData.ContainsKey($Name)) {
        return @{ Found = $false; Value = $null; Valid = $false }
    }

    $valid = $true
    if ($ValidationPattern -and $value -notmatch $ValidationPattern) {
        $valid = $false
    }

    return @{ Found = $EnvData.ContainsKey($Name); Value = $value; Valid = $valid }
}
