# AI_Docker_Launcher.ps1 - Main launcher with setup and launch options
# This script can be compiled to .exe using ps2exe

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
        $logEntry = "[$timestamp] [$Level] [LAUNCHER] $Message"
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if logging doesn't work - don't break the app
    }
}

Write-AppLog "========================================" "INFO"
Write-AppLog "AI Docker Launcher Started" "INFO"
Write-AppLog "Log file: $script:LogFile" "INFO"
Write-AppLog "========================================" "INFO"

# Version information
$script:AppVersion = "1.0.0"
$script:GitHubRepo = "Cainmani/ai-docker-cli-setup"

# Function to check for updates
function Check-ForUpdates {
    try {
        Write-AppLog "Checking for updates..." "DEBUG"
        $releaseUrl = "https://api.github.com/repos/$script:GitHubRepo/releases/latest"
        $response = Invoke-RestMethod -Uri $releaseUrl -Method Get -TimeoutSec 5 -ErrorAction Stop

        $latestVersion = $response.tag_name -replace '^v', ''
        Write-AppLog "Latest version: $latestVersion, Current version: $script:AppVersion" "DEBUG"

        if ($latestVersion -and ($latestVersion -ne $script:AppVersion)) {
            # Compare versions
            $current = [Version]$script:AppVersion
            $latest = [Version]$latestVersion

            if ($latest -gt $current) {
                Write-AppLog "Update available: $latestVersion" "INFO"
                return @{
                    UpdateAvailable = $true
                    CurrentVersion = $script:AppVersion
                    LatestVersion = $latestVersion
                    DownloadUrl = $response.assets | Where-Object { $_.name -like "*.exe" } | Select-Object -First 1 -ExpandProperty browser_download_url
                    ReleaseUrl = $response.html_url
                    ReleaseNotes = $response.body
                }
            }
        }
        return @{ UpdateAvailable = $false }
    } catch {
        Write-AppLog "Update check failed: $($_.Exception.Message)" "DEBUG"
        return @{ UpdateAvailable = $false; Error = $_.Exception.Message }
    }
}

# Matrix Green Theme Colors
$script:MatrixGreen = [System.Drawing.Color]::FromArgb(0, 255, 65)
$script:MatrixDarkGreen = [System.Drawing.Color]::FromArgb(0, 20, 0)
$script:MatrixMidGreen = [System.Drawing.Color]::FromArgb(0, 40, 10)
$script:MatrixAccent = [System.Drawing.Color]::FromArgb(0, 180, 50)

# Get script directory (works for both .ps1 and .exe) - robust method
Write-AppLog "Detecting script path..." "DEBUG"
Write-AppLog "PSScriptRoot: [$PSScriptRoot]" "DEBUG"
Write-AppLog "MyInvocation.MyCommand.Path: [$($MyInvocation.MyCommand.Path)]" "DEBUG"
Write-AppLog "Get-Location: [$(Get-Location)]" "DEBUG"

if ($PSScriptRoot) {
    $scriptPath = $PSScriptRoot
    Write-AppLog "Using PSScriptRoot: [$scriptPath]" "DEBUG"
} elseif ($MyInvocation.MyCommand.Path) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    Write-AppLog "Using MyInvocation.MyCommand.Path: [$scriptPath]" "DEBUG"
} else {
    # Fallback: use current directory (convert to string)
    $scriptPath = (Get-Location).Path
    Write-AppLog "Using Get-Location fallback: [$scriptPath]" "DEBUG"
}

# Final safety - ensure it's ALWAYS a valid string path (never null, never PathInfo)
if (-not $scriptPath) {
    $scriptPath = [System.IO.Directory]::GetCurrentDirectory()
    Write-AppLog "scriptPath was null, using CurrentDirectory: [$scriptPath]" "WARN"
}
if ($scriptPath -is [System.Management.Automation.PathInfo]) {
    Write-AppLog "scriptPath is PathInfo object, converting to string" "DEBUG"
    $scriptPath = $scriptPath.Path
}
# Force conversion to string to prevent Join-Path parameter binding errors
$scriptPath = [string]$scriptPath
Write-AppLog "scriptPath after string conversion: [$scriptPath]" "DEBUG"
if (-not $scriptPath) {
    # Ultimate fallback
    $scriptPath = $env:TEMP
    Write-AppLog "scriptPath still null, using TEMP fallback: [$scriptPath]" "ERROR"
}

Write-AppLog "Final scriptPath: [$scriptPath]" "INFO"

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = ">>> AI CLI DOCKER MANAGER <<<"
$form.Width = 600
$form.Height = 550
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:MatrixDarkGreen
$form.ForeColor = $script:MatrixGreen
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# Header
$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Left = 20; $lblHeader.Top = 20
$lblHeader.Width = 560; $lblHeader.Height = 30
$lblHeader.Text = "============================================================"
$lblHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblHeader.ForeColor = $script:MatrixGreen
$lblHeader.BackColor = 'Transparent'
$lblHeader.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Left = 20; $lblTitle.Top = 50
$lblTitle.Width = 560; $lblTitle.Height = 30
$lblTitle.Text = "AI CLI DOCKER MANAGEMENT SYSTEM"
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblTitle.ForeColor = $script:MatrixGreen
$lblTitle.BackColor = 'Transparent'
$lblTitle.Font = New-Object System.Drawing.Font('Consolas', 11, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblTitle)

$lblFooter = New-Object System.Windows.Forms.Label
$lblFooter.Left = 20; $lblFooter.Top = 80
$lblFooter.Width = 560; $lblFooter.Height = 30
$lblFooter.Text = "============================================================"
$lblFooter.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblFooter.ForeColor = $script:MatrixGreen
$lblFooter.BackColor = 'Transparent'
$lblFooter.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblFooter)

# Description
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Left = 20; $lblDesc.Top = 120
$lblDesc.Width = 560; $lblDesc.Height = 60
$lblDesc.Text = "Select an option below to manage your AI Docker environment:`n`nFirst time? Run 'First Time Setup' to install everything.`nAlready setup? Use 'Launch AI Workspace' for daily access."
$lblDesc.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblDesc.ForeColor = $script:MatrixGreen
$lblDesc.BackColor = 'Transparent'
$lblDesc.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($lblDesc)

# Button 1: First Time Setup
$btnSetup = New-Object System.Windows.Forms.Button
$btnSetup.Text = "1. FIRST TIME SETUP"
$btnSetup.Left = 50; $btnSetup.Top = 200
$btnSetup.Width = 500; $btnSetup.Height = 60
$btnSetup.FlatStyle = 'Flat'
$btnSetup.FlatAppearance.BorderColor = $script:MatrixAccent
$btnSetup.FlatAppearance.BorderSize = 2
$btnSetup.BackColor = $script:MatrixMidGreen
$btnSetup.ForeColor = $script:MatrixGreen
$btnSetup.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnSetup)

$lblSetupInfo = New-Object System.Windows.Forms.Label
$lblSetupInfo.Left = 70; $lblSetupInfo.Top = 265
$lblSetupInfo.Width = 460; $lblSetupInfo.Height = 20
$lblSetupInfo.Text = "Installs Docker image and AI CLI tools (5-10 minutes)"
$lblSetupInfo.ForeColor = $script:MatrixGreen
$lblSetupInfo.BackColor = 'Transparent'
$lblSetupInfo.Font = New-Object System.Drawing.Font('Consolas', 8)
$form.Controls.Add($lblSetupInfo)

# Button 2: Launch AI Workspace
$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = "2. LAUNCH AI WORKSPACE"
$btnLaunch.Left = 50; $btnLaunch.Top = 295
$btnLaunch.Width = 500; $btnLaunch.Height = 60
$btnLaunch.FlatStyle = 'Flat'
$btnLaunch.FlatAppearance.BorderColor = $script:MatrixAccent
$btnLaunch.FlatAppearance.BorderSize = 2
$btnLaunch.BackColor = $script:MatrixMidGreen
$btnLaunch.ForeColor = $script:MatrixGreen
$btnLaunch.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnLaunch)

$lblLaunchInfo = New-Object System.Windows.Forms.Label
$lblLaunchInfo.Left = 70; $lblLaunchInfo.Top = 360
$lblLaunchInfo.Width = 460; $lblLaunchInfo.Height = 20
$lblLaunchInfo.Text = "Opens workspace terminal (requires setup to be completed)"
$lblLaunchInfo.ForeColor = $script:MatrixGreen
$lblLaunchInfo.BackColor = 'Transparent'
$lblLaunchInfo.Font = New-Object System.Drawing.Font('Consolas', 8)
$form.Controls.Add($lblLaunchInfo)

# Status label for loading feedback
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Left = 20; $lblStatus.Top = 390
$lblStatus.Width = 560; $lblStatus.Height = 24
$lblStatus.Text = ""
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 0)  # Yellow/Gold for visibility
$lblStatus.BackColor = 'Transparent'
$lblStatus.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblStatus)

# Separator line above Exit button
$lblSeparator = New-Object System.Windows.Forms.Label
$lblSeparator.Left = 20; $lblSeparator.Top = 420
$lblSeparator.Width = 560; $lblSeparator.Height = 20
$lblSeparator.Text = "============================================================"
$lblSeparator.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblSeparator.ForeColor = $script:MatrixGreen
$lblSeparator.BackColor = 'Transparent'
$lblSeparator.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblSeparator)

# Button 3: Exit
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Left = 250; $btnExit.Top = 455
$btnExit.Width = 100; $btnExit.Height = 35
$btnExit.FlatStyle = 'Flat'
$btnExit.FlatAppearance.BorderColor = $script:MatrixAccent
$btnExit.FlatAppearance.BorderSize = 2
$btnExit.BackColor = $script:MatrixMidGreen
$btnExit.ForeColor = $script:MatrixGreen
$btnExit.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnExit)

# Event Handlers
$btnSetup.Add_Click({
    Write-AppLog "First Time Setup button clicked" "INFO"

    $setupScript = Join-Path $scriptPath "setup_wizard.ps1"
    Write-AppLog "Setup script path: [$setupScript]" "DEBUG"

    if (Test-Path $setupScript) {
        Write-AppLog "Setup script found, launching..." "INFO"

        # Show loading feedback BEFORE hiding the form
        $lblStatus.Text = ">>> LOADING SETUP WIZARD... <<<"
        $btnSetup.Enabled = $false
        $btnLaunch.Enabled = $false
        $btnExit.Enabled = $false
        [System.Windows.Forms.Application]::DoEvents()  # Force UI update
        Write-AppLog "Loading indicator shown, buttons disabled" "DEBUG"

        # Brief pause so user sees the loading message
        Start-Sleep -Milliseconds 500

        $form.Hide()

        # Check if SHIFT is held - enables DEV MODE (UI testing without destructive operations)
        $devModeArg = ""
        if ([System.Windows.Forms.Control]::ModifierKeys -eq [System.Windows.Forms.Keys]::Shift) {
            $devModeArg = " -DevMode"
            Write-AppLog "DEV MODE: Shift key detected - launching setup wizard in DEV mode" "INFO"
        }

        # Build argument list - ensure -DevMode is properly passed as separate argument
        $argList = "-ExecutionPolicy Bypass -File `"$setupScript`""
        if ($devModeArg) {
            $argList = "$argList -DevMode"
            Write-AppLog "Launch arguments: $argList" "DEBUG"
        }

        # Show console window for progress visibility (helps users see what's happening)
        # DEV MODE (Shift+Click) shows minimized console, normal mode shows normal console
        Write-AppLog "Starting setup wizard process..." "INFO"
        if ($devModeArg) {
            # DEV MODE: Normal console window for full debug visibility
            Write-AppLog "DEV MODE: Launching with visible console for debug output" "INFO"
            $process = Start-Process powershell.exe -ArgumentList $argList -Wait -PassThru
        } else {
            # NORMAL MODE: Show console (minimized) so user can see progress if needed
            # This prevents the "nothing happening" experience when wizard takes time to load
            Write-AppLog "Normal mode: Launching with minimized console (visible if needed)" "DEBUG"
            $process = Start-Process powershell.exe -ArgumentList $argList -WindowStyle Minimized -Wait -PassThru
        }
        Write-AppLog "Setup wizard process completed with exit code: $($process.ExitCode)" "INFO"

        # Reset UI state
        $lblStatus.Text = ""
        $btnSetup.Enabled = $true
        $btnLaunch.Enabled = $true
        $btnExit.Enabled = $true

        $form.Show()
        if ($process.ExitCode -eq 0) {
            Write-AppLog "Setup completed successfully" "INFO"
            [System.Windows.Forms.MessageBox]::Show("Setup wizard completed successfully!`n`nYou can now use 'Launch AI Workspace' to access your environment.", "Setup Complete", 'OK', 'Information')
        } else {
            Write-AppLog "Setup exited with non-zero code (cancelled or failed)" "WARN"
        }
        # If exit code is non-zero (e.g., 1 = cancelled), don't show success message
    } else {
        Write-AppLog "ERROR: Setup script not found at: $setupScript" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error: setup_wizard.ps1 not found in the same directory as this launcher.`n`nPath: $setupScript", "File Not Found", 'OK', 'Error')
    }
})

$btnLaunch.Add_Click({
    Write-AppLog "Launch AI Workspace button clicked" "INFO"

    # Check if SHIFT is held - warn user this is not supported for Launch
    if ([System.Windows.Forms.Control]::ModifierKeys -eq [System.Windows.Forms.Keys]::Shift) {
        Write-AppLog "Shift key detected on Launch button - showing warning" "WARN"
        [System.Windows.Forms.MessageBox]::Show("Shift+Click is only supported on 'First Time Setup' button for DEV MODE.`n`nTo launch your workspace normally, just click without holding Shift.", "Shift Key Detected", 'OK', 'Information')
        return
    }

    # Add error handling for path construction
    Write-AppLog "Constructing launch script path..." "DEBUG"
    Write-AppLog "scriptPath value: [$scriptPath]" "DEBUG"
    Write-AppLog "scriptPath type: $($scriptPath.GetType().FullName)" "DEBUG"

    try {
        if (-not $scriptPath) {
            Write-AppLog "ERROR: scriptPath is null!" "ERROR"
            throw "Script path is null. Please restart the launcher."
        }
        $launchScript = Join-Path $scriptPath "launch_claude.ps1"
        Write-AppLog "Launch script path constructed: [$launchScript]" "DEBUG"
    } catch {
        Write-AppLog "ERROR constructing launch script path: $($_.Exception.Message)" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error: Failed to locate scripts.`n`nDetails: $($_.Exception.Message)`n`nScript Path: $scriptPath", "Path Error", 'OK', 'Error')
        return
    }

    if (Test-Path $launchScript) {
        Write-AppLog "Launch script found: [$launchScript]" "INFO"

        # CRITICAL FIX: Check for existing container BEFORE checking .env
        # This prevents offering to delete a container when .env is accidentally missing
        Write-AppLog "Checking for existing ai-cli container..." "DEBUG"
        $existingContainer = docker ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>$null
        Write-AppLog "Container check result: [$existingContainer]" "DEBUG"

        if ($existingContainer -eq "ai-cli") {
            Write-AppLog "Container 'ai-cli' found - launching workspace..." "INFO"

            $form.Hide()
            # Launch workspace with hidden console (no debug output visible to user)
            # Use -WindowStyle parameter of Start-Process, not in ArgumentList
            Write-AppLog "Starting launch_claude.ps1 process..." "INFO"
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$launchScript`"" -WindowStyle Hidden
            Write-AppLog "Workspace launch process started successfully" "INFO"

            # Don't wait for launcher - let it run independently
            Start-Sleep -Seconds 1
            $form.Close()
        } else {
            Write-AppLog "Container 'ai-cli' not found - checking setup status..." "WARN"

            # No container exists - check if setup was ever run
            $envFile = Join-Path $scriptPath ".env"
            Write-AppLog "Checking for .env file at: [$envFile]" "DEBUG"

            if (-not (Test-Path $envFile)) {
                Write-AppLog ".env file not found - setup has not been completed" "WARN"
                # Neither container nor .env exists - user needs to run setup
                $result = [System.Windows.Forms.MessageBox]::Show(
                    "Setup has not been completed yet.`n`n" +
                    "No AI Docker container was found on your system.`n`n" +
                    "Would you like to run the First Time Setup now?",
                    "Setup Required",
                    'YesNo',
                    'Warning'
                )
                Write-AppLog "User response to setup prompt: $result" "INFO"
                if ($result -eq 'Yes') {
                    $btnSetup.PerformClick()
                }
                return
            } else {
                Write-AppLog ".env file exists but container is missing" "WARN"
                # .env exists but container is missing - offer to recreate
                $result = [System.Windows.Forms.MessageBox]::Show(
                    "Configuration file exists, but the Docker container is missing.`n`n" +
                    "The container may have been manually deleted.`n`n" +
                    "Would you like to run First Time Setup to recreate it?",
                    "Container Missing",
                    'YesNo',
                    'Warning'
                )
                Write-AppLog "User response to recreate prompt: $result" "INFO"
                if ($result -eq 'Yes') {
                    $btnSetup.PerformClick()
                }
                return
            }
        }
    } else {
        Write-AppLog "ERROR: Launch script not found at: [$launchScript]" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error: launch_claude.ps1 not found in the same directory as this launcher.`n`nPath: $launchScript", "File Not Found", 'OK', 'Error')
    }
})

$btnExit.Add_Click({
    $form.Close()
})

# Check if Docker Desktop is running on startup
Write-AppLog "Checking if Docker Desktop is running..." "DEBUG"
function Test-DockerRunning {
    try {
        $result = docker info 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

$dockerRunning = Test-DockerRunning
if (-not $dockerRunning) {
    Write-AppLog "Docker Desktop is not running" "WARN"

    $dockerMessage = "Docker Desktop is not running!`n`n" +
                     "This application requires Docker Desktop to be running.`n`n" +
                     "Would you like to open Docker Desktop now?`n`n" +
                     "Yes = Open Docker Desktop for me`n" +
                     "No = I'll open it myself`n" +
                     "Cancel = Exit the application"

    $result = [System.Windows.Forms.MessageBox]::Show(
        $dockerMessage,
        "Docker Desktop Required",
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-AppLog "User chose to open Docker Desktop" "INFO"
        # Try to start Docker Desktop
        $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerPath) {
            Start-Process $dockerPath
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not find Docker Desktop.`n`n" +
                "Please open it manually from your Start Menu.",
                "Docker Desktop Not Found",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }

        # Keep checking until Docker is running or user cancels
        $keepWaiting = $true
        while ($keepWaiting) {
            $waitResult = [System.Windows.Forms.MessageBox]::Show(
                "Waiting for Docker Desktop to start...`n`n" +
                "This usually takes 20-30 seconds.`n`n" +
                "Click 'Retry' to check if Docker is ready.`n" +
                "Click 'Cancel' to exit.",
                "Waiting for Docker",
                [System.Windows.Forms.MessageBoxButtons]::RetryCancel,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($waitResult -eq [System.Windows.Forms.DialogResult]::Cancel) {
                Write-AppLog "User cancelled while waiting for Docker" "INFO"
                exit 0
            }

            # User clicked Retry - check if Docker is running now
            if (Test-DockerRunning) {
                Write-AppLog "Docker is now running" "INFO"
                $keepWaiting = $false
            } else {
                Write-AppLog "Docker still not running, user will retry" "DEBUG"
            }
        }
    } elseif ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
        Write-AppLog "User cancelled - exiting application" "INFO"
        exit 0
    } else {
        # User clicked No - they want to continue without Docker (their choice)
        Write-AppLog "User chose to continue without Docker" "WARN"
    }
}

# Check for updates on startup (non-blocking)
Write-AppLog "Performing startup update check..." "DEBUG"
$updateInfo = Check-ForUpdates
if ($updateInfo.UpdateAvailable) {
    Write-AppLog "Update available: v$($updateInfo.LatestVersion)" "INFO"
    $updateMessage = "A new version is available!`n`n" +
                     "Current: v$($updateInfo.CurrentVersion)`n" +
                     "Latest: v$($updateInfo.LatestVersion)`n`n" +
                     "Would you like to open the download page?"

    $result = [System.Windows.Forms.MessageBox]::Show(
        $updateMessage,
        "Update Available",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-AppLog "User chose to open download page" "INFO"
        Start-Process $updateInfo.ReleaseUrl
    }
}

# Show form
[void]$form.ShowDialog()
