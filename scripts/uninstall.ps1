# uninstall.ps1 - Supported uninstall flow for AI Docker CLI Manager
#
# Removes the Docker container and image created by the setup wizard.
# SAFE DEFAULTS:
#   - Named volumes (Claude auth, tool auth, router data, Vibe Kanban data) are
#     KEPT unless -RemoveVolumes is passed.
#   - The AI_Work workspace folder on the Windows host is NEVER touched.
#   - App data (logs, extracted files, .env) is KEPT unless -RemoveAppData is passed.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1                 # container + image only
#   powershell ... -File uninstall.ps1 -RemoveVolumes                      # also delete auth/data volumes
#   powershell ... -File uninstall.ps1 -RemoveVolumes -RemoveAppData       # full uninstall
#   powershell ... -File uninstall.ps1 -Force                              # skip confirmation prompts

param(
    [switch]$RemoveVolumes,   # Also remove named volumes (Claude auth, tool auth, etc.)
    [switch]$RemoveAppData,   # Also remove %LOCALAPPDATA%\AI-Docker-CLI (logs, extracted files, .env)
    [switch]$Force            # Skip confirmation prompts (for scripted use)
)

$ErrorActionPreference = 'Continue'

# ---------- logging (shared module when available, fallback otherwise) ----------
$script:LogComponent = "UNINSTALL"
$logUtils = Join-Path $PSScriptRoot 'log_utils.ps1'
if (Test-Path $logUtils) {
    . $logUtils
} else {
    function Write-AppLog { param([string]$Message, [string]$Level = 'INFO') }
}

# Docker helpers (Find-Docker) when available
$dockerHelpers = Join-Path $PSScriptRoot 'docker_helpers.ps1'
if (Test-Path $dockerHelpers) {
    . $dockerHelpers
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AI DOCKER CLI MANAGER - UNINSTALL" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-AppLog "Uninstall started (RemoveVolumes=$RemoveVolumes, RemoveAppData=$RemoveAppData, Force=$Force)" "INFO"

# ---------- locate docker ----------
$dockerCmd = $null
if (Get-Command Find-Docker -ErrorAction SilentlyContinue) {
    $dockerCmd = Find-Docker
}
if (-not $dockerCmd) {
    $found = Get-Command docker -ErrorAction SilentlyContinue
    if ($found) { $dockerCmd = $found.Source }
}
if (-not $dockerCmd) {
    Write-Host "[WARNING] Docker not found - skipping container/image/volume removal." -ForegroundColor Yellow
    Write-AppLog "Docker not found - skipping Docker resource cleanup" "WARN"
} else {
    # ---------- confirm ----------
    if (-not $Force) {
        Write-Host "This will remove:" -ForegroundColor Yellow
        Write-Host "  - Docker container 'ai-cli'" -ForegroundColor Yellow
        Write-Host "  - Docker image 'ai-docker-cli' (and legacy-named images)" -ForegroundColor Yellow
        if ($RemoveVolumes) {
            Write-Host "  - Named volumes (Claude auth, tool auth, router data, Vibe Kanban data, SSH keys)" -ForegroundColor Red
        } else {
            Write-Host "  (Named volumes with your Claude auth and tool data are KEPT)" -ForegroundColor Green
        }
        Write-Host "  Your AI_Work workspace folder is NEVER touched." -ForegroundColor Green
        Write-Host ""
        $answer = Read-Host "Continue? (y/N)"
        if ($answer -notmatch '^[Yy]') {
            Write-Host "[INFO] Uninstall cancelled." -ForegroundColor Cyan
            Write-AppLog "Uninstall cancelled by user" "INFO"
            exit 2
        }
    }

    # ---------- remove container ----------
    Write-Host "[STEP] Removing container 'ai-cli'..." -ForegroundColor Cyan
    $existingContainer = & $dockerCmd ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>$null
    if ($existingContainer -eq 'ai-cli') {
        & $dockerCmd stop ai-cli 2>$null | Out-Null
        & $dockerCmd rm ai-cli 2>$null | Out-Null
        Write-Host "[OK] Container removed" -ForegroundColor Green
        Write-AppLog "Container ai-cli removed" "INFO"
    } else {
        Write-Host "[OK] No ai-cli container found" -ForegroundColor Green
    }

    # ---------- remove images (canonical + legacy names) ----------
    Write-Host "[STEP] Removing Docker images..." -ForegroundColor Cyan
    $imageNames = @('ai-docker-cli', 'docker-files-ai', 'ai-docker-ai', 'docker-ai')
    foreach ($imageName in $imageNames) {
        $img = & $dockerCmd images -q $imageName 2>$null
        if ($img) {
            & $dockerCmd rmi -f $imageName 2>$null | Out-Null
            Write-Host "[OK] Removed image: $imageName" -ForegroundColor Green
            Write-AppLog "Removed image $imageName" "INFO"
        }
    }

    # ---------- remove volumes (opt-in only) ----------
    if ($RemoveVolumes) {
        Write-Host "[STEP] Removing named volumes..." -ForegroundColor Cyan
        # Volumes are prefixed with the compose project name. Cover the fixed
        # project name ('ai-docker') plus legacy folder-derived prefixes.
        $volumeSuffixes = @('claude-config', 'vibe-kanban-data', 'ssh-keys', 'tool-auth', 'router-data')
        $projectPrefixes = @('ai-docker', 'docker-files', 'docker')
        $allVolumes = & $dockerCmd volume ls --format "{{.Name}}" 2>$null
        foreach ($vol in $allVolumes) {
            foreach ($prefix in $projectPrefixes) {
                foreach ($suffix in $volumeSuffixes) {
                    if ($vol -eq "${prefix}_${suffix}") {
                        & $dockerCmd volume rm $vol 2>$null | Out-Null
                        Write-Host "[OK] Removed volume: $vol" -ForegroundColor Green
                        Write-AppLog "Removed volume $vol" "INFO"
                    }
                }
            }
        }
    } else {
        Write-Host "[INFO] Named volumes kept (use -RemoveVolumes to delete them)" -ForegroundColor Cyan
    }
}

# ---------- remove app data (opt-in only) ----------
if ($RemoveAppData) {
    $appDataDir = Join-Path $env:LOCALAPPDATA "AI-Docker-CLI"
    if ($appDataDir -and (Test-Path $appDataDir)) {
        if (-not $Force) {
            $answer = Read-Host "Also delete app data at '$appDataDir' (logs, config)? (y/N)"
            if ($answer -notmatch '^[Yy]') {
                Write-Host "[INFO] App data kept." -ForegroundColor Cyan
                $appDataDir = $null
            }
        }
        if ($appDataDir) {
            Remove-Item -Path $appDataDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] App data removed: $appDataDir" -ForegroundColor Green
        }
    }
} else {
    Write-Host "[INFO] App data kept (use -RemoveAppData to delete logs/config)" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  UNINSTALL COMPLETE" -ForegroundColor Green
Write-Host "  Your AI_Work workspace folder was not modified." -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-AppLog "Uninstall complete" "INFO"
exit 0
