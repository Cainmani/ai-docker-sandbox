# AI_Docker_Complete.ps1 - Complete self-contained installer
# This script contains all files embedded and will extract them on first run

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Use AppData for all persistent files - makes this a true self-contained app
# Ensure LOCALAPPDATA is set (robust fallback)
if (-not $env:LOCALAPPDATA) {
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE "AppData\Local"
}
if (-not $env:LOCALAPPDATA) {
    # Ultimate fallback
    $env:LOCALAPPDATA = [System.IO.Path]::GetTempPath()
}

$appDataDir = Join-Path $env:LOCALAPPDATA "AI_Docker_Manager"
if (-not (Test-Path $appDataDir)) {
    New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null
}

# Create subfolder for Docker-related files
$filesDir = Join-Path $appDataDir "docker-files"
if (-not (Test-Path $filesDir)) {
    New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
}

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
        $logEntry = "[$timestamp] [$Level] [COMPLETE] $Message"
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if logging doesn't work - don't break the app
    }
}

Write-AppLog "========================================" "INFO"
Write-AppLog "AI Docker Complete (Standalone) Started" "INFO"
Write-AppLog "Log file: $script:LogFile" "INFO"
Write-AppLog "AppData directory: $appDataDir" "INFO"
Write-AppLog "Files directory: $filesDir" "INFO"
Write-AppLog "========================================" "INFO"

# Matrix Green Theme Colors
$script:MatrixGreen = [System.Drawing.Color]::FromArgb(0, 255, 65)
$script:MatrixDarkGreen = [System.Drawing.Color]::FromArgb(0, 20, 0)
$script:MatrixMidGreen = [System.Drawing.Color]::FromArgb(0, 40, 10)
$script:MatrixAccent = [System.Drawing.Color]::FromArgb(0, 180, 50)

# Embedded files as Base64 - stored in memory, only extracted when Docker needs them
$script:EmbeddedFiles = @{
    'setup_wizard.ps1' = 'SETUP_WIZARD_PS1_BASE64_HERE'
    'launch_claude.ps1' = 'LAUNCH_CLAUDE_PS1_BASE64_HERE'
    'docker-compose.yml' = 'DOCKER_COMPOSE_YML_BASE64_HERE'
    'Dockerfile' = 'DOCKERFILE_BASE64_HERE'
    'entrypoint.sh' = 'ENTRYPOINT_SH_BASE64_HERE'
    'claude_wrapper.sh' = 'CLAUDE_WRAPPER_SH_BASE64_HERE'
    'install_cli_tools.sh' = 'INSTALL_CLI_TOOLS_SH_BASE64_HERE'
    'auto_update.sh' = 'AUTO_UPDATE_SH_BASE64_HERE'
    'configure_tools.sh' = 'CONFIGURE_TOOLS_SH_BASE64_HERE'
    'fix_line_endings.ps1' = 'FIX_LINE_ENDINGS_PS1_BASE64_HERE'
    '.gitattributes' = '_GITATTRIBUTES_BASE64_HERE'
    'README.md' = 'README_MD_BASE64_HERE'
    'USER_MANUAL.md' = 'USER_MANUAL_MD_BASE64_HERE'
    'QUICK_REFERENCE.md' = 'QUICK_REFERENCE_MD_BASE64_HERE'
    'CLI_TOOLS_GUIDE.md' = 'CLI_TOOLS_GUIDE_MD_BASE64_HERE'
    'TESTING_CHECKLIST.md' = 'TESTING_CHECKLIST_MD_BASE64_HERE'
}

# Function to decode a file from Base64 to text
function Get-EmbeddedFileContent {
    param([string]$fileName)

    if ($script:EmbeddedFiles.ContainsKey($fileName)) {
        $bytes = [System.Convert]::FromBase64String($script:EmbeddedFiles[$fileName])
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    return $null
}

# Function to silently extract Docker-required files and documentation (no popups, no console output)
function Extract-DockerFiles {
    param([bool]$silent = $true)

    $dockerFiles = @('docker-compose.yml', 'Dockerfile', 'entrypoint.sh', 'claude_wrapper.sh', 'install_cli_tools.sh', 'auto_update.sh', 'configure_tools.sh', '.gitattributes', 'README.md', 'USER_MANUAL.md', 'QUICK_REFERENCE.md', 'CLI_TOOLS_GUIDE.md', 'TESTING_CHECKLIST.md')

    # Version tracking to detect when embedded files have been updated
    $versionFile = Join-Path $filesDir ".version"
    $currentVersion = [System.DateTime]::Now.ToString("yyyyMMddHHmmss")

    # Calculate hash of all embedded docker files to detect changes
    $hashBuilder = New-Object System.Text.StringBuilder
    foreach ($fileName in @('docker-compose.yml', 'Dockerfile', 'entrypoint.sh', 'install_cli_tools.sh', 'auto_update.sh', 'configure_tools.sh')) {
        $content = Get-EmbeddedFileContent $fileName
        if ($content) {
            $hashBuilder.Append($content) | Out-Null
        }
    }
    $currentHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($hashBuilder.ToString()))) -Algorithm SHA256).Hash

    # Check if files need updating
    $needsUpdate = $false
    $oldHash = ""
    if (Test-Path $versionFile) {
        $versionData = Get-Content $versionFile -Raw | ConvertFrom-Json
        $oldHash = $versionData.Hash
        if ($oldHash -ne $currentHash) {
            $needsUpdate = $true
        }
    } else {
        $needsUpdate = $true
    }

    # If docker files changed, only remove the IMAGE (not the container)
    # This forces a rebuild with new files while preserving user data in the container
    if ($needsUpdate -and $oldHash -ne "") {
        # Note: Removed Write-Host to prevent console window from appearing during updates

        # Check if container exists
        $existingContainer = docker ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>$null
        if ($existingContainer -eq "ai-cli") {
            # CRITICAL: Never delete the container automatically - user data is preserved
            # Only remove the old image to force rebuild
            try {
                $existingImage = docker images -q docker-files-ai 2>$null
                if ($existingImage) {
                    $null = docker rmi docker-files-ai 2>$null
                }
            } catch {
                # Ignore errors - image might be in use
            }
        } else {
            # No container exists - safe to remove image
            try {
                $null = docker rmi docker-files-ai 2>$null
            } catch {
                # Ignore errors - image might not exist
            }
        }
    }

    # Always extract files to ensure they're up-to-date (overwrites existing)
    foreach ($fileName in $dockerFiles) {
        $filePath = Join-Path $filesDir $fileName
        $content = Get-EmbeddedFileContent $fileName
        if ($content) {
            [System.IO.File]::WriteAllText($filePath, $content, [System.Text.UTF8Encoding]::new($false))
        }
    }

    # Update version file with new hash
    $versionData = @{
        Version = $currentVersion
        Hash = $currentHash
        UpdatedAt = [System.DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
    }
    $versionData | ConvertTo-Json | Out-File $versionFile -Encoding UTF8
}

# Now launch the main GUI
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

# Status label showing where app data is stored
$lblAppData = New-Object System.Windows.Forms.Label
$lblAppData.Left = 20; $lblAppData.Top = 390
$lblAppData.Width = 560; $lblAppData.Height = 40
$lblAppData.Text = "Configuration stored in:`n$appDataDir"
$lblAppData.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblAppData.ForeColor = $script:MatrixAccent
$lblAppData.BackColor = 'Transparent'
$lblAppData.Font = New-Object System.Drawing.Font('Consolas', 7)
$form.Controls.Add($lblAppData)

# Button 3: Exit
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Left = 250; $btnExit.Top = 440
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

    # Extract Docker files silently (needed for setup)
    Write-AppLog "Extracting Docker files..." "DEBUG"
    Extract-DockerFiles
    Write-AppLog "Docker files extracted" "DEBUG"

    # Get setup wizard content from memory
    Write-AppLog "Loading setup wizard from embedded resources..." "DEBUG"
    $setupContent = Get-EmbeddedFileContent 'setup_wizard.ps1'
    if ($setupContent) {
        Write-AppLog "Setup wizard loaded successfully" "DEBUG"
        # Extract setup wizard to subfolder
        $setupScript = Join-Path $filesDir "setup_wizard.ps1"
        Write-AppLog "Writing setup wizard to: [$setupScript]" "DEBUG"
        [System.IO.File]::WriteAllText($setupScript, $setupContent, [System.Text.UTF8Encoding]::new($false))
        Write-AppLog "Setup wizard written successfully" "DEBUG"

        try {
            $form.Hide()

            # Check if SHIFT is held - enables DEV MODE (UI testing without destructive operations)
            $devModeArg = ""
            if ([System.Windows.Forms.Control]::ModifierKeys -eq [System.Windows.Forms.Keys]::Shift) {
                $devModeArg = " -DevMode"
                Write-AppLog "DEV MODE: Shift key detected - launching setup wizard in DEV mode" "INFO"
            }

            # Run the setup wizard from subfolder
            # Build argument list - ensure -DevMode is properly passed as separate argument
            $argList = "-ExecutionPolicy Bypass -NoProfile -File `"$setupScript`""
            if ($devModeArg) {
                $argList = "$argList -DevMode"
                Write-AppLog "Launch arguments: $argList" "DEBUG"
            }

            # In DEV MODE, show console for debug output. In normal mode, hide it.
            Write-AppLog "Starting setup wizard process..." "INFO"
            if ($devModeArg) {
                # DEV MODE: Show console window so user can see debug messages
                Write-AppLog "DEV MODE: Launching with visible console for debug output" "INFO"
                $process = Start-Process powershell.exe -ArgumentList $argList -Wait -PassThru
            } else {
                # NORMAL MODE: Hide console for clean UX
                Write-AppLog "Normal mode: Launching with hidden console" "DEBUG"
                $process = Start-Process powershell.exe -ArgumentList $argList -WindowStyle Hidden -Wait -PassThru
            }
            Write-AppLog "Setup wizard process completed with exit code: $($process.ExitCode)" "INFO"
            $form.Show()

            # Handle different exit codes
            if ($process.ExitCode -eq 0) {
                Write-AppLog "Setup completed successfully" "INFO"
                # Success - show completion message
                # Check if .env was created in docker-files folder, then move it to main app directory
                $envFileInSubfolder = Join-Path $filesDir ".env"
                $envFileMain = Join-Path $appDataDir ".env"

                if (Test-Path $envFileInSubfolder) {
                    # Move .env to main app directory for easier access
                    Copy-Item $envFileInSubfolder $envFileMain -Force
                }

                # Different message for DEV mode
                if ($devModeArg) {
                    [System.Windows.Forms.MessageBox]::Show("DEV MODE: Setup wizard UI walkthrough completed.`n`nNo actual changes were made to the system.", "DEV MODE Complete", 'OK', 'Information')
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Setup wizard completed successfully!`n`nYou can now use 'Launch AI Workspace' to access your environment.`n`nConfiguration stored in:`n$appDataDir", "Setup Complete", 'OK', 'Information')
                }
            } elseif ($process.ExitCode -eq 1) {
                # Error/failure - show error message (but softer for DEV mode)
                if ($devModeArg) {
                    [System.Windows.Forms.MessageBox]::Show("DEV MODE: Wizard closed without completing all pages.`n`nThis is normal if you were just testing specific pages.", "DEV MODE Ended", 'OK', 'Information')
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Setup failed to complete.`n`nPlease check that:`n  - Docker Desktop is running`n  - All required files extracted successfully`n  - You have administrator privileges", "Setup Failed", 'OK', 'Error')
                }
            } elseif ($process.ExitCode -eq 2) {
                # User cancelled - exit silently (no message needed, user already saw cancellation confirmation)
            }
            # Exit codes: 0 = success, 1 = error, 2 = user cancelled
        } finally {
            # Optionally clean up the setup wizard file (or leave it for re-runs)
            # Remove-Item $setupScript -Force -ErrorAction SilentlyContinue
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Error: Setup wizard could not be loaded from embedded resources.", "Error", 'OK', 'Error')
    }
})

$btnLaunch.Add_Click({
    Write-AppLog "Launch AI Workspace button clicked" "INFO"

    # CRITICAL FIX: Check for existing container BEFORE checking .env
    # This prevents offering to delete a container when .env is accidentally missing
    Write-AppLog "Checking for existing ai-cli container..." "DEBUG"
    $existingContainer = docker ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>$null
    Write-AppLog "Container check result: [$existingContainer]" "DEBUG"

    if ($existingContainer -eq "ai-cli") {
        Write-AppLog "Container 'ai-cli' found - launching workspace..." "INFO"

        # Ensure docker-files subfolder exists
        if (-not (Test-Path $filesDir)) {
            Write-AppLog "Creating docker-files directory: [$filesDir]" "DEBUG"
            New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
        }

        # Copy .env if it exists, otherwise create a minimal one
        $envFileInSubfolder = Join-Path $filesDir ".env"
        $envFileMain = Join-Path $appDataDir ".env"
        if (Test-Path $envFileMain) {
            Write-AppLog "Copying .env from [$envFileMain] to [$envFileInSubfolder]" "DEBUG"
            Copy-Item $envFileMain $envFileInSubfolder -Force
        } else {
            Write-AppLog ".env file not found at [$envFileMain]" "DEBUG"
        }

        # Re-extract Docker files if they were deleted
        Write-AppLog "Re-extracting Docker files..." "DEBUG"
        Extract-DockerFiles
        Write-AppLog "Docker files extracted" "DEBUG"

        # Get launch script content from memory
        Write-AppLog "Loading launch script from embedded resources..." "DEBUG"
        $launchContent = Get-EmbeddedFileContent 'launch_claude.ps1'
        if ($launchContent) {
            Write-AppLog "Launch script loaded successfully" "DEBUG"
            # Extract launch script to subfolder
            $launchScript = Join-Path $filesDir "launch_claude.ps1"
            Write-AppLog "Writing launch script to: [$launchScript]" "DEBUG"
            [System.IO.File]::WriteAllText($launchScript, $launchContent, [System.Text.UTF8Encoding]::new($false))
            Write-AppLog "Launch script written successfully" "DEBUG"

            $form.Hide()
            # Run the launch script from subfolder with hidden console (no debug output visible to user)
            # Use -WindowStyle parameter of Start-Process, not in ArgumentList
            Write-AppLog "Starting launch_claude.ps1 process..." "INFO"
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$launchScript`"" -WindowStyle Hidden
            Write-AppLog "Workspace launch process started successfully" "INFO"

            # Wait a moment, then close the main form
            Start-Sleep -Milliseconds 500
            Write-AppLog "Closing main form" "INFO"
            $form.Close()
        } else {
            Write-AppLog "ERROR: Failed to load launch script from embedded resources" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("Error: Launch script could not be loaded from embedded resources.", "Error", 'OK', 'Error')
            $form.Show()
        }
    } else {
        Write-AppLog "Container 'ai-cli' not found - checking setup status..." "WARN"

        # No container exists - check if setup was ever run
        $envFileMain = Join-Path $appDataDir ".env"
        Write-AppLog "Checking for .env file at: [$envFileMain]" "DEBUG"

        if (-not (Test-Path $envFileMain)) {
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
})

$btnExit.Add_Click({
    $form.Close()
})

# Show form
[void]$form.ShowDialog()

