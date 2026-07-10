# setup_utils.ps1 - Shared setup utilities for AI Docker CLI Manager
# Provides line ending fixes, secure password cleanup, and npm validation.
# Usage: . "$PSScriptRoot\setup_utils.ps1"

# Resolves the docker files directory for a given script location.
# - Embedded exe layout (AppData\AI-Docker-CLI\docker-files): docker files sit next to the scripts
# - Project layout: docker files live in ..\docker relative to the scripts folder
function Resolve-DockerFilesPath {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    if ($ScriptPath -like '*AI-Docker-CLI*docker-files*') {
        return $ScriptPath
    }
    return (Join-Path $ScriptPath '..\docker')
}

# Builds the compose-file arguments for base and optional mobile access.
function Get-ComposeFileArgs {
    param(
        [Parameter(Mandatory)]
        [string]$DockerPath,

        [bool]$MobileAccess = $false
    )

    $composeArgs = 'compose -f docker-compose.yml'
    if ($MobileAccess) {
        $mobileOverride = Join-Path $DockerPath 'docker-compose.mobile.yml'
        if (-not (Test-Path $mobileOverride)) {
            throw "Mobile access requested but docker-compose.mobile.yml was not found at: $mobileOverride"
        }
        $composeArgs += ' -f docker-compose.mobile.yml'
    }
    return $composeArgs
}

# Validates a container password against the wizard's minimum requirements.
# Returns @{ Valid = [bool]; Message = [string] } so callers can show the reason.
function Test-PasswordStrength {
    param(
        [AllowEmptyString()]
        [string]$Password
    )

    if ([string]::IsNullOrEmpty($Password)) {
        return @{ Valid = $false; Message = 'Password cannot be empty.' }
    }
    if ($Password.Length -lt 8) {
        return @{ Valid = $false; Message = 'Password must be at least 8 characters long.' }
    }
    if ($Password -notmatch '[A-Za-z]' -or $Password -notmatch '[0-9]') {
        return @{ Valid = $false; Message = 'Password must contain at least one letter and one digit.' }
    }
    return @{ Valid = $true; Message = 'OK' }
}

function Fix-LineEndings {
    param([string]$scriptPath)

    # Docker files location - detect if running from embedded exe or project directory
    $dockerPath = Resolve-DockerFilesPath -ScriptPath $scriptPath
    $files = @('entrypoint.sh', 'install_cli_tools.sh', 'auto_update.sh', 'configure_tools.sh', 'setup_mobile_access.sh', 'add_ssh_key.sh', 'setup_remote_connection.sh')
    $fixed = $false

    foreach ($file in $files) {
        $filePath = Join-Path $dockerPath $file

        if (Test-Path $filePath) {
            $content = Get-Content $filePath -Raw

            if ($content -match "`r`n") {
                Write-Host "[AUTO-FIX] Converting $file to Unix line endings..." -ForegroundColor Yellow
                $content = $content -replace "`r`n", "`n"
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
                $fixed = $true
                Write-Host "[SUCCESS] Fixed: $file" -ForegroundColor Green
            }
        }
    }

    return $fixed
}

# Docker Compose requires the secret file to exist, so we replace the password with a placeholder
# instead of deleting it. This allows container restarts without "bind source path does not exist" errors.
function Replace-PasswordWithPlaceholder {
    param([string]$DockerPath)

    $secretsDir = Join-Path $DockerPath ".secrets"
    $passwordFile = Join-Path $secretsDir "password.txt"

    if (Test-Path $passwordFile) {
        $currentContent = Get-Content $passwordFile -Raw -ErrorAction SilentlyContinue

        # Skip if already replaced with placeholder
        if ($currentContent -eq "SETUP_COMPLETE") {
            Write-Host "[SECURITY] Password already replaced with placeholder" -ForegroundColor Green
            return
        }

        Write-Host "[SECURITY] Securely replacing password with placeholder..." -ForegroundColor Cyan

        try {
            # Get file size for overwrite
            $fileSize = (Get-Item $passwordFile).Length
            if ($fileSize -eq 0) { $fileSize = 64 }  # Minimum overwrite size

            # Overwrite with random data (3 passes for security)
            # Use Create()/GetBytes() rather than the static Fill() - Fill() only exists in
            # .NET Core 2.1+ (PowerShell 7), not in Windows PowerShell 5.1 (.NET Framework)
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            try {
                for ($pass = 1; $pass -le 3; $pass++) {
                    $randomBytes = New-Object byte[] $fileSize
                    $rng.GetBytes($randomBytes)
                    [System.IO.File]::WriteAllBytes($passwordFile, $randomBytes)
                    Write-Host "[SECURITY] Overwrite pass $pass complete" -ForegroundColor DarkGray
                }
            } finally {
                $rng.Dispose()
            }

            # Replace with placeholder instead of deleting
            Set-Content -Path $passwordFile -Value "SETUP_COMPLETE" -NoNewline
            Write-Host "[SECURITY] Password securely replaced with placeholder" -ForegroundColor Green
            Write-Host "[INFO] The placeholder allows container restarts while keeping the password secure" -ForegroundColor Gray
        } catch {
            Write-Host "[WARNING] Secure replacement failed: $($_.Exception.Message)" -ForegroundColor Yellow
            try {
                # Fallback: just write placeholder
                Set-Content -Path $passwordFile -Value "SETUP_COMPLETE" -NoNewline
                Write-Host "[SECURITY] Password replaced with placeholder (fallback method)" -ForegroundColor Yellow
            } catch {
                Write-Host "[ERROR] Could not replace password file - container restarts may fail" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "[SECURITY] Password file not found - creating placeholder for container restart support" -ForegroundColor Yellow
        try {
            # Ensure secrets directory exists
            if (-not (Test-Path $secretsDir)) {
                New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
            }
            Set-Content -Path $passwordFile -Value "SETUP_COMPLETE" -NoNewline
            Write-Host "[SECURITY] Placeholder created" -ForegroundColor Green
        } catch {
            Write-Host "[WARNING] Could not create placeholder file" -ForegroundColor Yellow
        }
    }
}

# Function to validate npm is working correctly (prevents "Unknown command: pm" errors)
# NOTE: Parallel implementation exists in docker/install_cli_tools.sh (validate_npm)
#       for the Linux container. Keep both in sync when making changes.
function Test-NpmFunctional {
    Write-Host "[INFO] Validating npm installation..." -ForegroundColor Cyan

    # Check if npm command exists
    $npmPath = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmPath) {
        Write-Host "[ERROR] npm not found in PATH" -ForegroundColor Red
        return @{ Valid = $false; Error = "npm not found in PATH"; NeedsInstall = $true }
    }

    # Verify npm can actually execute (catches "Unknown command: pm" type errors)
    try {
        $npmVersion = & $npmPath.Source --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] npm --version failed: $npmVersion" -ForegroundColor Red
            return @{ Valid = $false; Error = "npm not functioning: $npmVersion"; NeedsRepair = $true }
        }
    } catch {
        Write-Host "[ERROR] npm execution failed: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Valid = $false; Error = $_.Exception.Message; NeedsRepair = $true }
    }

    # Test npm can list global packages
    try {
        $listResult = & npm list -g --depth=0 2>&1
        if ($LASTEXITCODE -ne 0 -and $listResult -notmatch "empty") {
            Write-Host "[WARNING] npm global list had issues, but may still work" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[WARNING] Could not list npm global packages" -ForegroundColor Yellow
    }

    Write-Host "[OK] npm is functional (version: $npmVersion)" -ForegroundColor Green
    return @{ Valid = $true; Version = $npmVersion; Path = $npmPath.Source }
}

# Function to attempt npm repair
# NOTE: Parallel implementation exists in docker/install_cli_tools.sh (repair_npm)
function Repair-NpmInstallation {
    Write-Host "[INFO] Attempting to repair npm installation..." -ForegroundColor Yellow

    # Refresh PATH from system (Windows-only; harmless no-op on Linux)
    try {
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        if ($machinePath -or $userPath) {
            $env:Path = ($machinePath, $userPath | Where-Object { $_ }) -join ";"
        }
    } catch {
        Write-Host "[WARNING] Could not refresh PATH" -ForegroundColor Yellow
    }

    # Clear npm cache
    try {
        & npm cache clean --force 2>&1 | Out-Null
        Write-Host "[INFO] npm cache cleared" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARNING] Could not clear npm cache" -ForegroundColor Yellow
    }

    # Re-test npm
    return Test-NpmFunctional
}

# Function to create secure password file for Docker Secrets
function New-SecurePasswordFile {
    param([string]$Password, [string]$DockerPath)

    $secretsDir = Join-Path $DockerPath ".secrets"
    $passwordFile = Join-Path $secretsDir "password.txt"

    Write-Host "[SECURITY] Creating secure password file..." -ForegroundColor Cyan

    # Create .secrets directory if it doesn't exist
    if (-not (Test-Path $secretsDir)) {
        New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
        Write-Host "[SECURITY] Created .secrets directory" -ForegroundColor Green
    }

    # Write password to file (plain text - Docker will mount it as tmpfs)
    # Using UTF8 without BOM for Linux compatibility
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($passwordFile, $Password, $utf8NoBom)

    # Set restrictive permissions (Windows equivalent of chmod 600)
    # Use icacls rather than Set-Acl: Set-Acl also writes the owner/SACL sections of the
    # security descriptor, which requires SeSecurityPrivilege and fails ("does not possess
    # the 'SeSecurityPrivilege' privilege") in a normal non-elevated PowerShell session.
    # icacls only touches the DACL, which the file owner can always modify.
    if ($env:OS -eq 'Windows_NT') {
        try {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $icaclsOutput = & icacls.exe $passwordFile /inheritance:r /grant:r "${currentUser}:F" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "icacls exited with code ${LASTEXITCODE}: $icaclsOutput"
            }
            Write-Host "[SECURITY] Password file permissions restricted" -ForegroundColor Green
        } catch {
            Write-Host "[WARNING] Could not set restrictive permissions: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "[SECURITY] Password file created at: $passwordFile" -ForegroundColor Green
    return $passwordFile
}
