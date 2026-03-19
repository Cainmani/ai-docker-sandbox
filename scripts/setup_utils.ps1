# setup_utils.ps1 - Shared setup utilities for AI Docker CLI Manager
# Provides line ending fixes and secure password cleanup.
# Usage: . "$PSScriptRoot\setup_utils.ps1"

function Fix-LineEndings {
    param([string]$scriptPath)

    # Docker files location - detect if running from embedded exe or project directory
    $dockerPath = if ($scriptPath -like '*AI-Docker-CLI*docker-files*') {
        # Running from embedded exe - docker files are in same folder
        $scriptPath
    } else {
        # Running from project directory - docker files are in ../docker
        Join-Path $scriptPath '..\docker'
    }
    $files = @('entrypoint.sh', 'setup.sh', 'claude_wrapper.sh')
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
            $random = New-Object System.Random
            for ($pass = 1; $pass -le 3; $pass++) {
                $randomBytes = New-Object byte[] $fileSize
                $random.NextBytes($randomBytes)
                [System.IO.File]::WriteAllBytes($passwordFile, $randomBytes)
                Write-Host "[SECURITY] Overwrite pass $pass complete" -ForegroundColor DarkGray
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
