# launch_claude.ps1 - Direct Workspace Launcher (No GUI)
# This script directly launches the Docker workspace terminal without any intermediate dialogs

Add-Type -AssemblyName System.Windows.Forms  # Only needed for error dialogs

# ============================================================
# CENTRALIZED LOGGING SYSTEM (shared module)
# Log file location: %LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log
# ============================================================
$script:LogComponent = "LAUNCH_CLAUDE"
. "$PSScriptRoot\log_utils.ps1"
. "$PSScriptRoot\docker_helpers.ps1"
. "$PSScriptRoot\env_utils.ps1"

Write-AppLog "========================================" "INFO"
Write-AppLog "Launch Claude Script Started (Direct Launch Mode)" "INFO"
Write-AppLog "Log file: $script:LogFile" "INFO"
Write-AppLog "========================================" "INFO"

Write-AppLog "Initial environment check:" "DEBUG"
Write-AppLog "PSScriptRoot: [$PSScriptRoot]" "DEBUG"
Write-AppLog "MyInvocation.MyCommand.Path: [$($MyInvocation.MyCommand.Path)]" "DEBUG"
Write-AppLog "Get-Location: [$(Get-Location)]" "DEBUG"

# Ensure script directory is set correctly (robust method for all launch scenarios)
Write-AppLog "Detecting script path..." "DEBUG"
$scriptPath = if ($PSScriptRoot) {
    Write-AppLog "Using PSScriptRoot: [$PSScriptRoot]" "DEBUG"
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $path = Split-Path -Parent $MyInvocation.MyCommand.Path
    Write-AppLog "Using MyInvocation.MyCommand.Path: [$path]" "DEBUG"
    $path
} else {
    # Fallback: use current directory (convert to string)
    $path = (Get-Location).Path
    Write-AppLog "Using Get-Location fallback: [$path]" "DEBUG"
    $path
}

# Final safety - ensure it's ALWAYS a valid string path (never null, never PathInfo)
if (-not $scriptPath) {
    $scriptPath = [System.IO.Directory]::GetCurrentDirectory()
    Write-AppLog "scriptPath was null, set to CurrentDirectory: [$scriptPath]" "WARN"
}
if ($scriptPath -is [System.Management.Automation.PathInfo]) {
    Write-AppLog "scriptPath is PathInfo object, converting to Path property" "DEBUG"
    $scriptPath = $scriptPath.Path
}
# Force conversion to string to prevent Join-Path parameter binding errors
$scriptPath = [string]$scriptPath

if (-not $scriptPath) {
    # Ultimate fallback
    $scriptPath = $env:TEMP
    Write-AppLog "scriptPath still null after cast, using TEMP: [$scriptPath]" "ERROR"
}

Write-AppLog "Final scriptPath: [$scriptPath]" "INFO"

function ShowMsg($text, $icon='Information') {
    [System.Windows.Forms.MessageBox]::Show($text, "AI CLI Launcher", 'OK', $icon) | Out-Null
}

# ============================================================
# MAIN LAUNCH LOGIC (No GUI - Direct Execution)
# ============================================================

Write-AppLog "Starting workspace launch sequence..." "INFO"

# First check if Docker executable exists
Write-AppLog "Finding Docker executable..." "DEBUG"
$dockerPath = Find-Docker
if (-not $dockerPath) {
    Write-AppLog "ERROR: Docker not found" "ERROR"
    ShowMsg ("Docker is not installed or cannot be found.`n`nPlease install Docker Desktop from:`nhttps://docs.docker.com/desktop/setup/install/windows-install/") 'Error'
    exit 1
}
Write-AppLog "Docker found at: $dockerPath" "INFO"

# Check if Docker is running
Write-AppLog "Checking if Docker is running..." "DEBUG"
if (-not (DockerOk)) {
    Write-AppLog "Docker is not running - attempting to start Docker Desktop" "WARN"

    # Try to start Docker Desktop
    $dockerDesktop = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    Write-AppLog "Checking for Docker Desktop at: $dockerDesktop" "DEBUG"

    if (Test-Path $dockerDesktop) {
        Write-AppLog "Starting Docker Desktop..." "INFO"
        ShowMsg "Docker Desktop is not running.`n`nStarting Docker Desktop now...`n`nDocker will take 1-2 minutes to fully start.`nPlease wait..." 'Information'
        Start-Process $dockerDesktop

        # Wait for Docker to start (max 120 seconds = 2 minutes)
        $waited = 0
        while ($waited -lt 120 -and -not (DockerOk)) {
            Start-Sleep -Seconds 2
            $waited += 2
        }

        if (-not (DockerOk)) {
            Write-AppLog "Docker Desktop failed to start within 120 seconds" "ERROR"
            ShowMsg "Docker Desktop did not start within 2 minutes.`n`nPlease:`n  - Wait a bit longer and try launching again`n  - Check if Docker Desktop is starting (look for icon in system tray)`n  - Restart your computer if Docker Desktop appears stuck" 'Warning'
            exit 1
        }
        Write-AppLog "Docker Desktop started successfully" "INFO"
    } else {
        Write-AppLog "Docker Desktop executable not found at expected location" "WARN"
        ShowMsg "Docker Desktop is not running.`n`nTo fix this:`n  - Click the Start menu`n  - Search for 'Docker Desktop'`n  - Click to start Docker Desktop`n  - Wait for Docker to fully start`n  - Then try launching again" 'Warning'
        exit 1
    }
}

# Check if ai-cli container exists
Write-AppLog "Checking for ai-cli container..." "DEBUG"
$containerCheck = & $dockerPath ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>&1
Write-AppLog "Container check result: [$containerCheck]" "DEBUG"

if ($containerCheck -ne "ai-cli") {
    Write-AppLog "ERROR: ai-cli container does not exist" "ERROR"
    ShowMsg "The ai-cli container does not exist.`n`nPlease run the Setup Wizard first to create the container." 'Error'
    exit 1
}
Write-AppLog "Container 'ai-cli' exists" "INFO"

# Check if container is running, start if needed
Write-AppLog "Checking if container is running..." "DEBUG"
$containerStatus = & $dockerPath ps --filter "name=ai-cli" --format "{{.Names}}" 2>&1
Write-AppLog "Container status: [$containerStatus]" "DEBUG"

if ($containerStatus -ne "ai-cli") {
    Write-AppLog "Container is not running - starting container..." "INFO"
    Start-Process -FilePath $dockerPath -ArgumentList "start","ai-cli" -WindowStyle Hidden -Wait | Out-Null
    Start-Sleep -Seconds 2
    Write-AppLog "Container started" "INFO"
} else {
    Write-AppLog "Container is already running" "DEBUG"
}

# Read username from .env file - REQUIRED, no fallback
Write-AppLog "Reading username from .env..." "DEBUG"
$envFile = Join-Path $scriptPath ".env"
Write-AppLog "Attempting to read .env from: [$envFile]" "DEBUG"
$envData = Read-EnvFile -Path $envFile

if ($envData.Count -eq 0) {
    Write-AppLog ".env file not found or empty at [$envFile]" "ERROR"
}

$userResult = Get-EnvVar -EnvData $envData -Name 'USER_NAME' -ValidationPattern '^[a-z_][a-z0-9_-]{0,31}$'
$userName = $userResult.Value
if ($userName) {
    $script:ContainerUsername = $userName
    Write-AppLog "Username from .env: [$userName]" "DEBUG"
}

if (-not $userName) {
    Write-AppLog "ERROR: Could not determine username - .env file missing or invalid" "ERROR"
    ShowMsg "Configuration error: .env file is missing or invalid.`n`nPlease run 'First Time Setup' again to fix this." 'Error'
    exit 1
}

if (-not $userResult.Valid) {
    Write-AppLog "ERROR: Invalid username format in .env: [$userName]" "ERROR"
    ShowMsg "Configuration error: invalid username '$userName' in .env file.`n`nPlease run 'First Time Setup' again." 'Error'
    exit 1
}
Write-AppLog "Final username: [$userName]" "INFO"

# Build the docker exec command - connect as the user and start at /workspace
$dockerCmd = "`"$dockerPath`" exec -it -u $userName -w /workspace ai-cli bash -l"
Write-AppLog "Docker command: $dockerCmd" "DEBUG"

# Open terminal at /workspace directory
if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
    # Use Windows Terminal if available
    Write-AppLog "Launching Windows Terminal..." "INFO"
    Start-Process wt.exe "cmd.exe /k $dockerCmd"
} else {
    # Fallback to cmd - open new window with docker exec
    Write-AppLog "Launching cmd.exe (Windows Terminal not available)..." "INFO"
    Start-Process cmd.exe "/k $dockerCmd"
}

Write-AppLog "Workspace terminal launched successfully" "INFO"
Write-AppLog "Launch script completed" "INFO"
exit 0
