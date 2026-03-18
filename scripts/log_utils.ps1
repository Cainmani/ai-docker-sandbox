# log_utils.ps1 - Shared logging utilities for AI Docker CLI Manager
# Provides log sanitization and file logging used across all launcher scripts.
# Usage: . "$PSScriptRoot\log_utils.ps1"

# Log file location: %LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log
$script:LogDir = Join-Path $env:LOCALAPPDATA "AI-Docker-CLI\logs"
$script:LogFile = Join-Path $script:LogDir "ai-docker.log"

# Ensure log directory exists
if ($env:LOCALAPPDATA -and -not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force -ErrorAction SilentlyContinue | Out-Null
}

# Component tag for log entries (set by caller, e.g., "LAUNCHER", "LAUNCH_CLAUDE")
if (-not $script:LogComponent) { $script:LogComponent = "APP" }

# Container username (set by caller after reading .env, used by Sanitize-LogMessage)
$script:ContainerUsername = $null

function Sanitize-LogMessage {
    param([string]$Message)

    if (-not $Message) { return $Message }

    # Sanitize Windows username in paths
    $username = $env:USERNAME
    if ($username) {
        $Message = $Message -replace "\\$username\\", "\<USER>\"
        $Message = $Message -replace "/$username/", "/<USER>/"
    }

    # Sanitize container username (from .env) in log messages
    if ($script:ContainerUsername) {
        $Message = $Message -replace "\b$([regex]::Escape($script:ContainerUsername))\b", "<USER>"
    }

    # Sanitize API keys (OpenAI sk-proj-... and sk-... patterns)
    $Message = $Message -replace "sk-proj-[a-zA-Z0-9_-]{20,}", "<REDACTED_API_KEY>"
    $Message = $Message -replace "sk-[a-zA-Z0-9]{20,}", "<REDACTED_API_KEY>"
    $Message = $Message -replace "sk-ant-[a-zA-Z0-9_-]{20,}", "<REDACTED_API_KEY>"

    # Sanitize GitHub tokens
    $Message = $Message -replace "gh[pousr]_[a-zA-Z0-9]{36,}", "<REDACTED_TOKEN>"

    # Sanitize generic tokens/secrets/passwords
    $Message = $Message -replace "([Tt]oken)[=:]\s*[a-zA-Z0-9_-]{20,}", "`$1=<REDACTED>"
    $Message = $Message -replace "([Ss]ecret)[=:]\s*[a-zA-Z0-9_-]{20,}", "`$1=<REDACTED>"
    $Message = $Message -replace "([Pp]assword)[=:]\s*[^\s]+", "`$1=<REDACTED>"

    # Sanitize AWS keys
    $Message = $Message -replace "AKIA[A-Z0-9]{16}", "<REDACTED_AWS_KEY>"

    # Sanitize Google Cloud API keys
    $Message = $Message -replace "AIza[a-zA-Z0-9_-]{35}", "<REDACTED_GCP_KEY>"

    # Sanitize Bearer tokens
    $Message = $Message -replace "Bearer [a-zA-Z0-9_.-]{20,}", "Bearer <REDACTED>"

    # Sanitize JWT tokens
    $Message = $Message -replace "eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*", "<REDACTED_JWT>"

    return $Message
}

function Write-AppLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = $script:LogComponent
    )
    try {
        # Sanitize BEFORE writing
        $sanitizedMessage = Sanitize-LogMessage -Message $Message

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $logEntry = "[$timestamp] [$Level] [$Component] $sanitizedMessage"
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if logging doesn't work - don't break the app
    }
}
