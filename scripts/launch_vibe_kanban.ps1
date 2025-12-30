# launch_vibe_kanban.ps1 - Vibe Kanban Launcher
# This script starts Vibe Kanban in the Docker container and opens the web UI

Add-Type -AssemblyName System.Windows.Forms

# ============================================================
# CENTRALIZED LOGGING SYSTEM
# Log file location: %LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log
# ============================================================
$script:LogDir = Join-Path $env:LOCALAPPDATA "AI-Docker-CLI\logs"
$script:LogFile = Join-Path $script:LogDir "ai-docker.log"

# Ensure log directory exists
if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force -ErrorAction SilentlyContinue | Out-Null
}

function Write-AppLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"  # INFO, WARN, ERROR, DEBUG
    )
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $logEntry = "[$timestamp] [$Level] [VIBE_KANBAN] $Message"
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if logging doesn't work - don't break the app
    }
}

Write-AppLog "========================================" "INFO"
Write-AppLog "Vibe Kanban Launcher Started" "INFO"
Write-AppLog "Log file: $script:LogFile" "INFO"
Write-AppLog "========================================" "INFO"

# Get script directory
$scriptPath = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).Path
}
$scriptPath = [string]$scriptPath
Write-AppLog "Script path: [$scriptPath]" "DEBUG"

function ShowMsg($text, $icon='Information') {
    [System.Windows.Forms.MessageBox]::Show($text, "Vibe Kanban Launcher", 'OK', $icon) | Out-Null
}

function Find-Docker() {
    Write-AppLog "Finding Docker executable..." "DEBUG"
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCmd) {
        Write-AppLog "Docker found in PATH: $($dockerCmd.Source)" "DEBUG"
        return $dockerCmd.Source
    }

    $possiblePaths = @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe",
        "$env:ProgramW6432\Docker\Docker\resources\bin\docker.exe"
    )

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
        if (-not $dockerPath) { return $false }
        $p = Start-Process -FilePath $dockerPath -ArgumentList "info" -WindowStyle Hidden -PassThru -Wait
        return $p.ExitCode -eq 0
    } catch {
        Write-AppLog "Error checking Docker status: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================
# MAIN LAUNCH LOGIC
# ============================================================

Write-AppLog "Starting Vibe Kanban launch sequence..." "INFO"

# Find Docker
$dockerPath = Find-Docker
if (-not $dockerPath) {
    Write-AppLog "ERROR: Docker not found" "ERROR"
    ShowMsg "Docker is not installed or cannot be found.`n`nPlease install Docker Desktop first." 'Error'
    exit 1
}

# Check if Docker is running
if (-not (DockerOk)) {
    Write-AppLog "Docker is not running" "WARN"
    ShowMsg "Docker Desktop is not running.`n`nPlease start Docker Desktop and try again." 'Warning'
    exit 1
}

# Check if container exists
$containerCheck = & $dockerPath ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>&1
if ($containerCheck -ne "ai-cli") {
    Write-AppLog "ERROR: ai-cli container does not exist" "ERROR"
    ShowMsg "The ai-cli container does not exist.`n`nPlease run the Setup Wizard first." 'Error'
    exit 1
}

# Check if container is running, start if needed
$containerStatus = & $dockerPath ps --filter "name=ai-cli" --format "{{.Names}}" 2>&1
if ($containerStatus -ne "ai-cli") {
    Write-AppLog "Container is not running - starting..." "INFO"
    Start-Process -FilePath $dockerPath -ArgumentList "start","ai-cli" -WindowStyle Hidden -Wait | Out-Null
    Start-Sleep -Seconds 2
}

# Read username from .env file - REQUIRED, no fallback
$userName = $null
try {
    $envFile = Join-Path $scriptPath ".env"
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile
        foreach ($line in $envContent) {
            if ($line -match '^USER_NAME=(.+)$') {
                $userName = $matches[1]
                break
            }
        }
    } else {
        Write-AppLog ".env file not found at [$envFile]" "ERROR"
    }
} catch {
    Write-AppLog "ERROR reading .env file: $($_.Exception.Message)" "ERROR"
}

# If username not found, show error and exit - do NOT use fallback
if (-not $userName) {
    Write-AppLog "ERROR: Could not determine username - .env file missing or invalid" "ERROR"
    ShowMsg "Configuration error: .env file is missing or invalid.`n`nPlease run 'First Time Setup' again to fix this." 'Error'
    exit 1
}
Write-AppLog "Username: [$userName]" "INFO"

# Read Vibe Kanban port from .env (default 3000)
$vibeKanbanPort = "3000"
try {
    $envFile = Join-Path $scriptPath ".env"
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile
        foreach ($line in $envContent) {
            if ($line -match '^VIBE_KANBAN_PORT=(.+)$') {
                $vibeKanbanPort = $matches[1]
                break
            }
        }
    }
} catch {
    Write-AppLog "Using default port 3000" "DEBUG"
}
Write-AppLog "Vibe Kanban port: [$vibeKanbanPort]" "INFO"

# Check if Vibe Kanban is already running inside the container
# Note: We check by looking for a node process listening on the port, not just pgrep
# because pgrep -f can match itself and cause false positives
Write-AppLog "Checking if Vibe Kanban is already running in container..." "DEBUG"
$vibeKanbanRunning = $false
try {
    # Check if something is actually listening on the vibe-kanban port inside the container
    # Use netstat/ss to check for actual listeners, not pgrep which can match itself
    $portCheck = & $dockerPath exec -u $userName ai-cli bash -c "netstat -tlnp 2>/dev/null | grep ':$vibeKanbanPort ' || echo 'NOT_LISTENING'" 2>&1
    if ($portCheck -and $portCheck -notmatch 'NOT_LISTENING' -and $portCheck -match ':' + $vibeKanbanPort) {
        $vibeKanbanRunning = $true
        Write-AppLog "Vibe Kanban is listening on port $vibeKanbanPort inside container" "INFO"
    } else {
        Write-AppLog "Nothing listening on port $vibeKanbanPort inside container" "DEBUG"
    }
} catch {
    Write-AppLog "Port check failed, assuming not running: $($_.Exception.Message)" "DEBUG"
}

if ($vibeKanbanRunning) {
    # Already running, just open browser
    Write-AppLog "Opening browser to existing Vibe Kanban instance..." "INFO"
    Start-Process "http://localhost:$vibeKanbanPort"
    exit 0
}

# Check if Vibe Kanban is installed
Write-AppLog "Checking if Vibe Kanban is installed..." "DEBUG"
$vibeKanbanCheck = & $dockerPath exec -u $userName ai-cli bash -c "npm list -g vibe-kanban 2>/dev/null | grep vibe-kanban" 2>&1
if (-not $vibeKanbanCheck -or $vibeKanbanCheck -notmatch "vibe-kanban") {
    Write-AppLog "Vibe Kanban not installed" "WARN"
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Vibe Kanban is not installed in the container.`n`n" +
        "Would you like to install it now?`n`n" +
        "(This may take a few minutes)",
        "Vibe Kanban Not Found",
        'YesNo',
        'Question'
    )

    if ($result -eq 'Yes') {
        Write-AppLog "Installing Vibe Kanban..." "INFO"
        ShowMsg "Installing Vibe Kanban...`n`nThis may take a few minutes. Please wait." 'Information'

        $installResult = & $dockerPath exec -u $userName ai-cli bash -c "npm install -g vibe-kanban@latest" 2>&1
        Write-AppLog "Install result: $installResult" "DEBUG"

        # Verify installation
        $vibeKanbanCheck = & $dockerPath exec -u $userName ai-cli bash -c "npm list -g vibe-kanban 2>/dev/null | grep vibe-kanban" 2>&1
        if (-not $vibeKanbanCheck -or $vibeKanbanCheck -notmatch "vibe-kanban") {
            Write-AppLog "ERROR: Vibe Kanban installation failed" "ERROR"
            ShowMsg "Failed to install Vibe Kanban.`n`nPlease try running the setup wizard again." 'Error'
            exit 1
        }
        Write-AppLog "Vibe Kanban installed successfully" "INFO"
    } else {
        Write-AppLog "User declined installation" "INFO"
        exit 0
    }
}

# Start Vibe Kanban in the container
Write-AppLog "Starting Vibe Kanban server..." "INFO"
Write-AppLog "NOTE: First run may take 1-2 minutes to download required files (~26MB)" "INFO"

# First verify vibe-kanban binary location
$whichResult = & $dockerPath exec -u $userName ai-cli bash -c "which vibe-kanban 2>&1" 2>&1
Write-AppLog "vibe-kanban location: $whichResult" "DEBUG"

if (-not $whichResult -or $whichResult -match "not found" -or $whichResult -match "no vibe-kanban") {
    Write-AppLog "ERROR: vibe-kanban binary not found in PATH" "ERROR"

    # Check npm global bin directory
    $npmBin = & $dockerPath exec -u $userName ai-cli bash -c "npm bin -g 2>/dev/null" 2>&1
    Write-AppLog "npm global bin: $npmBin" "DEBUG"

    # Check if vibe-kanban exists there
    $checkNpmBin = & $dockerPath exec -u $userName ai-cli bash -c "ls -la `$(npm bin -g)/vibe-kanban 2>&1" 2>&1
    Write-AppLog "vibe-kanban in npm bin: $checkNpmBin" "DEBUG"

    ShowMsg "Vibe Kanban binary not found in PATH.`n`nThe installation may have failed. Please run First Time Setup again with 'Force Rebuild' checked." 'Error'
    exit 1
}

# Run Vibe Kanban in background with proper environment variables
# HOST=0.0.0.0 allows access from Windows host
# PORT is configurable via env var
# Use full path to ensure binary is found
$startCmd = "cd /workspace && HOST=0.0.0.0 PORT=$vibeKanbanPort nohup vibe-kanban > /tmp/vibe-kanban.log 2>&1 &"
Write-AppLog "Start command: $startCmd" "DEBUG"

$execResult = & $dockerPath exec -u $userName -w /workspace ai-cli bash -c $startCmd 2>&1
if ($execResult) {
    Write-AppLog "Exec output: $execResult" "DEBUG"
}

# Give it a moment to create the log file
Start-Sleep -Milliseconds 500

# Check if log file was created
$logExists = & $dockerPath exec -u $userName ai-cli bash -c "test -f /tmp/vibe-kanban.log && echo EXISTS || echo MISSING" 2>&1
Write-AppLog "Log file status: $logExists" "DEBUG"

# Check for immediate errors in log
$earlyLog = & $dockerPath exec -u $userName ai-cli bash -c "cat /tmp/vibe-kanban.log 2>/dev/null | head -10" 2>&1
if ($earlyLog) {
    Write-AppLog "Early log output: $earlyLog" "DEBUG"
}

# Wait for server to start (longer timeout for first-run download)
Write-AppLog "Waiting for Vibe Kanban to start (may take longer on first run)..." "INFO"
$maxWait = 90  # seconds - first run downloads ~26MB
$waited = 0
$serverStarted = $false

while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 1
    $waited++

    try {
        $tcpCheck = Test-NetConnection -ComputerName localhost -Port $vibeKanbanPort -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($tcpCheck.TcpTestSucceeded) {
            $serverStarted = $true
            Write-AppLog "Vibe Kanban started after $waited seconds" "INFO"
            break
        }
    } catch {
        # Continue waiting
    }
}

if (-not $serverStarted) {
    Write-AppLog "ERROR: Vibe Kanban failed to start within $maxWait seconds" "ERROR"

    # Try to get logs for debugging
    $logs = & $dockerPath exec -u $userName ai-cli bash -c "cat /tmp/vibe-kanban.log 2>/dev/null" 2>&1
    Write-AppLog "Vibe Kanban full log: $logs" "ERROR"

    # Check if process is running at all
    $processCheck = & $dockerPath exec -u $userName ai-cli bash -c "ps aux | grep -v grep | grep vibe-kanban" 2>&1
    Write-AppLog "Process check: $processCheck" "DEBUG"

    # Check if port is in use by something else
    $portInUse = & $dockerPath exec -u $userName ai-cli bash -c "netstat -tlnp 2>/dev/null | grep ':$vibeKanbanPort'" 2>&1
    Write-AppLog "Port $vibeKanbanPort status: $portInUse" "DEBUG"

    # Build error message with log excerpt
    $errorMsg = "Vibe Kanban failed to start after $maxWait seconds.`n`n"
    if ($logs -and $logs.Length -gt 0) {
        # Show last 5 lines of log in error message
        $logLines = $logs -split "`n" | Select-Object -Last 5
        $errorMsg += "Log output:`n$($logLines -join "`n")`n`n"
    } else {
        $errorMsg += "No log output captured (log file may not have been created).`n`n"
    }
    $errorMsg += "Check the full log at:`n%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log"

    ShowMsg $errorMsg 'Error'
    exit 1
}

# Open browser
Write-AppLog "Opening browser to http://localhost:$vibeKanbanPort" "INFO"
Start-Process "http://localhost:$vibeKanbanPort"

Write-AppLog "Vibe Kanban launched successfully" "INFO"
exit 0
