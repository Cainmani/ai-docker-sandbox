# env_utils.ps1 - Shared .env file parsing utilities for AI Docker CLI Manager
# Provides .env file reading, variable extraction, and atomic key updates.
# Usage: . "$PSScriptRoot\env_utils.ps1"
# NOTE: Must remain Windows PowerShell 5.1 compatible.

# Strip one pair of matching surrounding quotes ("..." or '...') from a value.
function ConvertFrom-EnvValue {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) { return $Value }
    if ($Value.Length -ge 2) {
        $first = $Value[0]
        $last = $Value[$Value.Length - 1]
        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            return $Value.Substring(1, $Value.Length - 2)
        }
    }
    return $Value
}

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

        # Parse KEY=VALUE (strip matching surrounding quotes from the value)
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $result[$Matches[1]] = ConvertFrom-EnvValue -Value $Matches[2]
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

# Validate a TCP port value (string or int). Returns $true for 1-65535.
function Test-PortValue {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        $Port
    )

    if ($null -eq $Port) { return $false }
    $portString = "$Port".Trim()
    if ($portString -notmatch '^\d{1,5}$') { return $false }
    $portNumber = [int]$portString
    return ($portNumber -ge 1 -and $portNumber -le 65535)
}

# Backward-compatible name used by launchers.
function Test-ValidPort {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )

    return Test-PortValue -Port $Value
}

# Resolve the canonical .env file for source and packaged layouts.
function Resolve-EnvFilePath {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $localEnv = Join-Path $ScriptPath '.env'
    $parent = Split-Path -Parent $ScriptPath
    if ($parent) {
        $dockerDir = Join-Path $parent 'docker'
        $dockerEnv = Join-Path $dockerDir '.env'
        if (Test-Path (Join-Path $dockerDir 'docker-compose.yml')) {
            return $dockerEnv
        }
    }

    return $localEnv
}

# Internal: write lines to a file atomically (temp file + rename).
# Preserves other keys/comments; callers pass the full desired content.
function Write-EnvFileAtomic {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrEmpty($directory)) { $directory = '.' }
    $tempPath = Join-Path $directory ((Split-Path -Leaf $Path) + '.tmp.' + [Guid]::NewGuid().ToString('N'))

    try {
        # ASCII-safe UTF8 without BOM; .env files must not carry a BOM
        $content = ($Lines -join "`r`n")
        if ($Lines.Count -gt 0) { $content += "`r`n" }
        [System.IO.File]::WriteAllText($tempPath, $content, (New-Object System.Text.UTF8Encoding($false)))

        # Atomic-as-possible replace on Windows: Move-Item with -Force replaces the target
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
        return $true
    } catch {
        if (Test-Path $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

# Set (add or update) KEY=VALUE in a .env file atomically.
# Preserves comments, blank lines, ordering, and unrelated keys.
function Set-EnvKey {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Value = ''
    )

    # Quote values containing whitespace or # so they round-trip through Read-EnvFile
    $storedValue = $Value
    if ($storedValue -match '\s|#') {
        $storedValue = '"' + $storedValue + '"'
    }
    $newLine = "$Key=$storedValue"

    $lines = @()
    if (Test-Path $Path) {
        $lines = @(Get-Content $Path)
    }

    $updated = $false
    $outLines = @()
    foreach ($line in $lines) {
        if (-not $updated -and $line -match "^\s*$([regex]::Escape($Key))=") {
            $outLines += $newLine
            $updated = $true
        } else {
            $outLines += $line
        }
    }
    if (-not $updated) {
        $outLines += $newLine
    }

    return Write-EnvFileAtomic -Path $Path -Lines $outLines
}

# Remove KEY from a .env file atomically. Returns $true if the file was
# rewritten (or the key was absent / file missing - nothing to do).
function Remove-EnvKey {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
        [string]$Key
    )

    if (-not (Test-Path $Path)) { return $true }

    $lines = @(Get-Content $Path)
    $outLines = @()
    $removed = $false
    foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Key))=") {
            $removed = $true
            continue
        }
        $outLines += $line
    }

    if (-not $removed) { return $true }

    return Write-EnvFileAtomic -Path $Path -Lines $outLines
}
