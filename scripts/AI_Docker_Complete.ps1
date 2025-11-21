# AI_Docker_Complete.ps1 - Complete self-contained installer
# This script contains all files embedded and will extract them on first run

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Use AppData for all persistent files - makes this a true self-contained app
$appDataDir = Join-Path $env:LOCALAPPDATA "AI_Docker_Manager"
if (-not (Test-Path $appDataDir)) {
    New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null
}

# Create subfolder for Docker-related files
$filesDir = Join-Path $appDataDir "docker-files"
if (-not (Test-Path $filesDir)) {
    New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
}

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

    # If docker files changed, clean up old containers/images automatically
    if ($needsUpdate -and $oldHash -ne "") {
        try {
            # Silently clean up old container and image to force rebuild with new files
            $null = docker stop ai-cli 2>$null
            $null = docker rm ai-cli 2>$null
            $null = docker rmi docker-files-ai 2>$null
        } catch {
            # Ignore errors - container/image might not exist
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
    # Extract Docker files silently (needed for setup)
    Extract-DockerFiles

    # Get setup wizard content from memory
    $setupContent = Get-EmbeddedFileContent 'setup_wizard.ps1'
    if ($setupContent) {
        # Extract setup wizard to subfolder
        $setupScript = Join-Path $filesDir "setup_wizard.ps1"
        [System.IO.File]::WriteAllText($setupScript, $setupContent, [System.Text.UTF8Encoding]::new($false))

        try {
            $form.Hide()

            # Check if SHIFT is held - enables DEV MODE (UI testing without destructive operations)
            $devModeArg = ""
            if ([System.Windows.Forms.Control]::ModifierKeys -eq [System.Windows.Forms.Keys]::Shift) {
                $devModeArg = " -DevMode"
                Write-Host "[DEV MODE] Shift key detected - launching setup wizard in DEV mode" -ForegroundColor Magenta
            }

            # Run the setup wizard from subfolder with minimized window (GUI scripts can't be fully hidden)
            $process = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Minimized -File `"$setupScript`"$devModeArg" -Wait -PassThru
            $form.Show()

            # Handle different exit codes
            if ($process.ExitCode -eq 0) {
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
    # Check if .env exists in AppData directory
    $envFileMain = Join-Path $appDataDir ".env"
    if (-not (Test-Path $envFileMain)) {
        $result = [System.Windows.Forms.MessageBox]::Show("Setup has not been completed yet.`n`nWould you like to run the First Time Setup now?", "Setup Required", 'YesNo', 'Warning')
        if ($result -eq 'Yes') {
            $btnSetup.PerformClick()
        }
        return
    }

    # Ensure docker-files subfolder exists and copy .env there for the launch script to use
    if (-not (Test-Path $filesDir)) {
        New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
    }

    # Copy .env from main app directory to docker-files folder for launch script to access
    $envFileInSubfolder = Join-Path $filesDir ".env"
    Copy-Item $envFileMain $envFileInSubfolder -Force

    # Re-extract Docker files if they were deleted
    Extract-DockerFiles

    # Get launch script content from memory
    $launchContent = Get-EmbeddedFileContent 'launch_claude.ps1'
    if ($launchContent) {
        # Extract launch script to subfolder
        $launchScript = Join-Path $filesDir "launch_claude.ps1"
        [System.IO.File]::WriteAllText($launchScript, $launchContent, [System.Text.UTF8Encoding]::new($false))

        $form.Hide()
        # Run the launch script from subfolder with minimized window
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Minimized -File `"$launchScript`""

        # Wait a moment, then close the main form
        Start-Sleep -Milliseconds 500
        $form.Close()
    } else {
        [System.Windows.Forms.MessageBox]::Show("Error: Launch script could not be loaded from embedded resources.", "Error", 'OK', 'Error')
        $form.Show()
    }
})

$btnExit.Add_Click({
    $form.Close()
})

# Show form
[void]$form.ShowDialog()

