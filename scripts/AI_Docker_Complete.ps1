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

$appDataDir = Join-Path $env:LOCALAPPDATA "AI-Docker-CLI"
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

function Sanitize-LogMessage {
    param([string]$Message)

    # Sanitize Windows username in paths
    $username = $env:USERNAME
    if ($username) {
        $Message = $Message -replace "\\$username\\", "\<USER>\"
        $Message = $Message -replace "/$username/", "/<USER>/"
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
        [string]$Level = "INFO"
    )
    try {
        # Sanitize BEFORE writing
        $sanitizedMessage = Sanitize-LogMessage -Message $Message

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $logEntry = "[$timestamp] [$Level] [COMPLETE] $sanitizedMessage"
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

# ============================================================
# CONFIGURATION - Edit these values if forking/moving the repo
# ============================================================
$script:AppVersion = "1.2.1"
$script:GitHubRepo = "Cainmani/ai-docker-cli-setup"
$script:DockerDesktopPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"

# Function to check for updates
function Check-ForUpdates {
    try {
        Write-AppLog "Checking for updates..." "DEBUG"
        $releaseUrl = "https://api.github.com/repos/$script:GitHubRepo/releases/latest"
        $response = Invoke-RestMethod -Uri $releaseUrl -Method Get -TimeoutSec 5 -ErrorAction Stop

        $latestVersion = $response.tag_name -replace '^v', ''
        Write-AppLog "Latest version: $latestVersion, Current version: $script:AppVersion" "DEBUG"

        if ($latestVersion -and ($latestVersion -ne $script:AppVersion)) {
            # Validate version strings before comparison
            $current = $null
            $latest = $null
            if (-not [Version]::TryParse($script:AppVersion, [ref]$current)) {
                Write-AppLog "Invalid current version format: $script:AppVersion" "WARN"
                return @{ UpdateAvailable = $false }
            }
            if (-not [Version]::TryParse($latestVersion, [ref]$latest)) {
                Write-AppLog "Invalid latest version format from API: $latestVersion" "WARN"
                return @{ UpdateAvailable = $false }
            }

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

# Embedded files as Base64 - stored in memory, only extracted when Docker needs them
$script:EmbeddedFiles = @{
    'setup_wizard.ps1' = 'SETUP_WIZARD_PS1_BASE64_HERE'
    'launch_claude.ps1' = 'LAUNCH_CLAUDE_PS1_BASE64_HERE'
    'launch_vibe_kanban.ps1' = 'LAUNCH_VIBE_KANBAN_PS1_BASE64_HERE'
    'docker-compose.yml' = 'DOCKER_COMPOSE_YML_BASE64_HERE'
    'Dockerfile' = 'DOCKERFILE_BASE64_HERE'
    '.dockerignore' = '_DOCKERIGNORE_BASE64_HERE'
    'entrypoint.sh' = 'ENTRYPOINT_SH_BASE64_HERE'
    'claude_wrapper.sh' = 'CLAUDE_WRAPPER_SH_BASE64_HERE'
    'install_cli_tools.sh' = 'INSTALL_CLI_TOOLS_SH_BASE64_HERE'
    'auto_update.sh' = 'AUTO_UPDATE_SH_BASE64_HERE'
    'configure_tools.sh' = 'CONFIGURE_TOOLS_SH_BASE64_HERE'
    'setup_mobile_access.sh' = 'SETUP_MOBILE_ACCESS_SH_BASE64_HERE'
    'add_ssh_key.sh' = 'ADD_SSH_KEY_SH_BASE64_HERE'
    'tmux.conf' = 'TMUX_CONF_BASE64_HERE'
    'lib/logging.sh' = 'LOGGING_SH_BASE64_HERE'
    'fix_line_endings.ps1' = 'FIX_LINE_ENDINGS_PS1_BASE64_HERE'
    '.gitattributes' = '_GITATTRIBUTES_BASE64_HERE'
    'README.md' = 'README_MD_BASE64_HERE'
    'USER_MANUAL.md' = 'USER_MANUAL_MD_BASE64_HERE'
    'QUICK_REFERENCE.md' = 'QUICK_REFERENCE_MD_BASE64_HERE'
    'CLI_TOOLS_GUIDE.md' = 'CLI_TOOLS_GUIDE_MD_BASE64_HERE'
    'REMOTE_ACCESS.md' = 'REMOTE_ACCESS_MD_BASE64_HERE'
    'TESTING_CHECKLIST.md' = 'TESTING_CHECKLIST_MD_BASE64_HERE'
}

# ============================================================
# STARTUP VALIDATION - Detect if .exe was built incorrectly
# ============================================================
# Placeholder format: FILENAME (uppercase, underscores) + "_BASE64_HERE" suffix
# The build script replaces these with actual Base64-encoded file contents.
# If placeholders remain, it means the build process failed or was skipped.
function Test-EmbeddedFilesValid {
    foreach ($key in $script:EmbeddedFiles.Keys) {
        $content = $script:EmbeddedFiles[$key]
        # Match placeholder pattern: starts with optional underscore, uppercase letters/underscores, ends with _BASE64_HERE
        if ($content -match "^_?[A-Z][A-Z0-9_]*_BASE64_HERE$") {
            return @{
                Valid = $false
                Message = "File '$key' contains placeholder: $content"
            }
        }
    }
    return @{ Valid = $true }
}

$validation = Test-EmbeddedFilesValid
if (-not $validation.Valid) {
    Write-AppLog "BUILD ERROR: Embedded files contain placeholders - exe not built correctly" "ERROR"
    Write-AppLog $validation.Message "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        "ERROR: This executable was not built correctly.`n`n" +
        "$($validation.Message)`n`n" +
        "The build script (build_complete_exe.ps1) must be run to embed all files.`n`n" +
        "Please rebuild the .exe and try again.",
        "Build Error",
        'OK',
        'Error'
    )
    exit 1
}
Write-AppLog "Embedded files validation passed" "DEBUG"

# Function to decode a file from Base64 to text (with error handling)
function Get-EmbeddedFileContent {
    param([string]$fileName)

    if ($script:EmbeddedFiles.ContainsKey($fileName)) {
        try {
            $bytes = [System.Convert]::FromBase64String($script:EmbeddedFiles[$fileName])
            return [System.Text.Encoding]::UTF8.GetString($bytes)
        } catch {
            Write-AppLog "ERROR: Failed to decode $fileName - invalid Base64 content: $($_.Exception.Message)" "ERROR"
            return $null
        }
    }
    Write-AppLog "WARNING: File $fileName not found in embedded resources" "WARN"
    return $null
}

# Function to silently extract Docker-required files and documentation (no popups, no console output)
function Extract-DockerFiles {
    param([bool]$silent = $true)

    $dockerFiles = @('docker-compose.yml', 'Dockerfile', '.dockerignore', 'entrypoint.sh', 'claude_wrapper.sh', 'install_cli_tools.sh', 'auto_update.sh', 'configure_tools.sh', 'setup_mobile_access.sh', 'add_ssh_key.sh', 'tmux.conf', 'lib/logging.sh', '.gitattributes', 'README.md', 'USER_MANUAL.md', 'QUICK_REFERENCE.md', 'CLI_TOOLS_GUIDE.md', 'REMOTE_ACCESS.md', 'TESTING_CHECKLIST.md')

    # Version tracking to detect when embedded files have been updated
    $versionFile = Join-Path $filesDir ".version"
    $currentVersion = [System.DateTime]::Now.ToString("yyyyMMddHHmmss")

    # Calculate hash of all embedded docker files to detect changes
    $hashBuilder = New-Object System.Text.StringBuilder
    foreach ($fileName in @('docker-compose.yml', 'Dockerfile', 'entrypoint.sh', 'install_cli_tools.sh', 'auto_update.sh', 'configure_tools.sh', 'setup_mobile_access.sh', 'add_ssh_key.sh', 'tmux.conf', 'lib/logging.sh')) {
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

    # Create lib subdirectory for logging library
    $libDir = Join-Path $filesDir "lib"
    if (-not (Test-Path $libDir)) {
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
    }

    # Always extract files to ensure they're up-to-date (overwrites existing)
    foreach ($fileName in $dockerFiles) {
        $filePath = Join-Path $filesDir $fileName
        # Ensure parent directory exists for nested paths like lib/logging.sh
        $parentDir = Split-Path $filePath -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
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
$form.Height = 690
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

# Button 3: Launch Vibe Kanban
$btnVibeKanban = New-Object System.Windows.Forms.Button
$btnVibeKanban.Text = "3. LAUNCH VIBE KANBAN"
$btnVibeKanban.Left = 50; $btnVibeKanban.Top = 390
$btnVibeKanban.Width = 500; $btnVibeKanban.Height = 60
$btnVibeKanban.FlatStyle = 'Flat'
$btnVibeKanban.FlatAppearance.BorderColor = $script:MatrixAccent
$btnVibeKanban.FlatAppearance.BorderSize = 2
$btnVibeKanban.BackColor = $script:MatrixMidGreen
$btnVibeKanban.ForeColor = $script:MatrixGreen
$btnVibeKanban.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnVibeKanban)

$lblVibeKanbanInfo = New-Object System.Windows.Forms.Label
$lblVibeKanbanInfo.Left = 70; $lblVibeKanbanInfo.Top = 455
$lblVibeKanbanInfo.Width = 460; $lblVibeKanbanInfo.Height = 20
$lblVibeKanbanInfo.Text = "Opens AI agent orchestration web UI (http://localhost:3000)"
$lblVibeKanbanInfo.ForeColor = $script:MatrixGreen
$lblVibeKanbanInfo.BackColor = 'Transparent'
$lblVibeKanbanInfo.Font = New-Object System.Drawing.Font('Consolas', 8)
$form.Controls.Add($lblVibeKanbanInfo)

# Status label for loading feedback
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Left = 20; $lblStatus.Top = 485
$lblStatus.Width = 560; $lblStatus.Height = 24
$lblStatus.Text = ""
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 0)  # Yellow/Gold for visibility
$lblStatus.BackColor = 'Transparent'
$lblStatus.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblStatus)

# Status label showing where app data is stored
$lblAppData = New-Object System.Windows.Forms.Label
$lblAppData.Left = 20; $lblAppData.Top = 510
$lblAppData.Width = 560; $lblAppData.Height = 40
$lblAppData.Text = "Configuration stored in:`n$appDataDir"
$lblAppData.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblAppData.ForeColor = $script:MatrixAccent
$lblAppData.BackColor = 'Transparent'
$lblAppData.Font = New-Object System.Drawing.Font('Consolas', 7)
$form.Controls.Add($lblAppData)

# Button 4: Exit
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Left = 250; $btnExit.Top = 555
$btnExit.Width = 100; $btnExit.Height = 35
$btnExit.FlatStyle = 'Flat'
$btnExit.FlatAppearance.BorderColor = $script:MatrixAccent
$btnExit.FlatAppearance.BorderSize = 2
$btnExit.BackColor = $script:MatrixMidGreen
$btnExit.ForeColor = $script:MatrixGreen
$btnExit.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnExit)

# Footer with version and Report Issue link
$lblVersion = New-Object System.Windows.Forms.Label
$lblVersion.Left = 20; $lblVersion.Top = 605
$lblVersion.Width = 280; $lblVersion.Height = 20
$lblVersion.Text = "v$script:AppVersion"
$lblVersion.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblVersion.ForeColor = [System.Drawing.Color]::FromArgb(100, 150, 100)  # Dimmer green
$lblVersion.BackColor = 'Transparent'
$lblVersion.Font = New-Object System.Drawing.Font('Consolas', 8)
$form.Controls.Add($lblVersion)

$lblReportIssue = New-Object System.Windows.Forms.LinkLabel
$lblReportIssue.Left = 300; $lblReportIssue.Top = 605
$lblReportIssue.Width = 280; $lblReportIssue.Height = 20
$lblReportIssue.Text = "Report Issue"
$lblReportIssue.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblReportIssue.LinkColor = $script:MatrixAccent
$lblReportIssue.ActiveLinkColor = $script:MatrixGreen
$lblReportIssue.VisitedLinkColor = $script:MatrixAccent
$lblReportIssue.BackColor = 'Transparent'
$lblReportIssue.Font = New-Object System.Drawing.Font('Consolas', 8)
$lblReportIssue.Add_LinkClicked({
    Write-AppLog "Report Issue link clicked" "INFO"

    # Open Windows Explorer to logs folder
    Start-Process "explorer.exe" -ArgumentList $script:LogDir

    # Show instructions
    [System.Windows.Forms.MessageBox]::Show(
        "The logs folder has been opened.`n`n" +
        "To report an issue:`n" +
        "1. Drag and drop the log files into the GitHub issue form`n" +
        "2. Describe your issue`n`n" +
        "Log files are already sanitized - safe to share publicly.",
        "Report Issue",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    # Open GitHub issue template
    Start-Process "https://github.com/$script:GitHubRepo/issues/new?template=bug_report.yml"
})
$form.Controls.Add($lblReportIssue)

# Event Handlers
$btnSetup.Add_Click({
    Write-AppLog "First Time Setup button clicked" "INFO"

    # Show loading feedback immediately
    $lblStatus.Text = ">>> LOADING SETUP WIZARD... <<<"
    $btnSetup.Enabled = $false
    $btnLaunch.Enabled = $false
    $btnVibeKanban.Enabled = $false
    $btnExit.Enabled = $false
    [System.Windows.Forms.Application]::DoEvents()  # Force UI update
    Write-AppLog "Loading indicator shown, buttons disabled" "DEBUG"

    try {
        # Extract Docker files silently (needed for setup)
        $lblStatus.Text = ">>> EXTRACTING FILES... <<<"
        [System.Windows.Forms.Application]::DoEvents()
        Write-AppLog "Extracting Docker files..." "DEBUG"
        Extract-DockerFiles
        Write-AppLog "Docker files extracted" "DEBUG"

        # Get setup wizard content from memory
        $lblStatus.Text = ">>> PREPARING WIZARD... <<<"
        [System.Windows.Forms.Application]::DoEvents()
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
                $lblStatus.Text = ">>> LAUNCHING WIZARD... <<<"
                [System.Windows.Forms.Application]::DoEvents()

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

                # Start wizard process WITHOUT -Wait so we can keep showing status
                Write-AppLog "Starting setup wizard process..." "INFO"
                if ($devModeArg) {
                    Write-AppLog "DEV MODE: Launching with visible console for debug output" "INFO"
                    $process = Start-Process powershell.exe -ArgumentList $argList -PassThru
                } else {
                    Write-AppLog "Normal mode: Launching with minimized console (visible if needed)" "DEBUG"
                    $process = Start-Process powershell.exe -ArgumentList $argList -WindowStyle Minimized -PassThru
                }

                # Keep menu visible with status while wizard loads
                # Wait for wizard window to appear (poll for process to have a main window)
                $lblStatus.Text = ">>> WAITING FOR WIZARD WINDOW... <<<"
                [System.Windows.Forms.Application]::DoEvents()

                $maxWaitMs = 5000  # Max 5 seconds
                $waited = 0
                while ($waited -lt $maxWaitMs -and -not $process.HasExited) {
                    Start-Sleep -Milliseconds 100
                    $waited += 100
                    [System.Windows.Forms.Application]::DoEvents()

                    # Check if process has a main window handle (wizard GUI is visible)
                    try {
                        $process.Refresh()
                        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
                            Write-AppLog "Wizard window detected after ${waited}ms" "DEBUG"
                            break
                        }
                    } catch {
                        # Process may have exited, continue
                    }
                }

                # Now hide the menu since wizard is visible (or timeout reached)
                $form.Hide()
                Write-AppLog "Menu hidden, waiting for wizard to complete..." "DEBUG"

                # Wait for wizard process to complete
                $process.WaitForExit()
                Write-AppLog "Setup wizard process completed with exit code: $($process.ExitCode)" "INFO"

                # Reset UI state
                $lblStatus.Text = ""
                $btnSetup.Enabled = $true
                $btnLaunch.Enabled = $true
                $btnVibeKanban.Enabled = $true
                $btnExit.Enabled = $true

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
            Write-AppLog "ERROR: Setup wizard content is null - could not be loaded" "ERROR"
            # Reset UI state on error
            $lblStatus.Text = ""
            $btnSetup.Enabled = $true
            $btnLaunch.Enabled = $true
            $btnVibeKanban.Enabled = $true
            $btnExit.Enabled = $true
            [System.Windows.Forms.MessageBox]::Show("Error: Setup wizard could not be loaded from embedded resources.`n`nCheck the log file for details:`n$script:LogFile", "Error", 'OK', 'Error')
        }
    } catch {
        # Catch any unhandled exceptions (file extraction, Base64 decode, etc.)
        Write-AppLog "ERROR: Exception in First Time Setup: $($_.Exception.Message)" "ERROR"
        Write-AppLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        # Reset UI state on error
        $lblStatus.Text = ""
        $btnSetup.Enabled = $true
        $btnLaunch.Enabled = $true
        $btnVibeKanban.Enabled = $true
        $btnExit.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred during setup:`n`n$($_.Exception.Message)`n`nPlease check the log file for details:`n$script:LogFile",
            "Setup Error",
            'OK',
            'Error'
        )
    }
})

$btnLaunch.Add_Click({
    Write-AppLog "Launch AI Workspace button clicked" "INFO"

    try {
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
            [System.Windows.Forms.MessageBox]::Show("Error: Launch script could not be loaded from embedded resources.`n`nCheck the log file for details:`n$script:LogFile", "Error", 'OK', 'Error')
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
    } catch {
        # Catch any unhandled exceptions in launch handler
        Write-AppLog "ERROR: Exception in Launch AI Workspace: $($_.Exception.Message)" "ERROR"
        Write-AppLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while launching the workspace:`n`n$($_.Exception.Message)`n`nPlease check the log file for details:`n$script:LogFile",
            "Launch Error",
            'OK',
            'Error'
        )
        $form.Show()
    }
})

$btnVibeKanban.Add_Click({
    Write-AppLog "Launch Vibe Kanban button clicked" "INFO"

    try {
        # Check for existing container
        Write-AppLog "Checking for existing ai-cli container..." "DEBUG"
        $existingContainer = docker ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>$null
        Write-AppLog "Container check result: [$existingContainer]" "DEBUG"

        if ($existingContainer -eq "ai-cli") {
            Write-AppLog "Container 'ai-cli' found - launching Vibe Kanban..." "INFO"

            # Ensure docker-files subfolder exists
            if (-not (Test-Path $filesDir)) {
                Write-AppLog "Creating docker-files directory: [$filesDir]" "DEBUG"
                New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
            }

            # Copy .env if it exists
            $envFileInSubfolder = Join-Path $filesDir ".env"
            $envFileMain = Join-Path $appDataDir ".env"
            if (Test-Path $envFileMain) {
                Write-AppLog "Copying .env from [$envFileMain] to [$envFileInSubfolder]" "DEBUG"
                Copy-Item $envFileMain $envFileInSubfolder -Force
            }

            # Re-extract Docker files if they were deleted
            Write-AppLog "Re-extracting Docker files..." "DEBUG"
            Extract-DockerFiles
            Write-AppLog "Docker files extracted" "DEBUG"

            # Get Vibe Kanban launch script content from memory
            Write-AppLog "Loading Vibe Kanban launch script from embedded resources..." "DEBUG"
            $vibeContent = Get-EmbeddedFileContent 'launch_vibe_kanban.ps1'
            if ($vibeContent) {
                Write-AppLog "Vibe Kanban launch script loaded successfully" "DEBUG"
                # Extract launch script to subfolder
                $vibeScript = Join-Path $filesDir "launch_vibe_kanban.ps1"
                Write-AppLog "Writing Vibe Kanban script to: [$vibeScript]" "DEBUG"
                [System.IO.File]::WriteAllText($vibeScript, $vibeContent, [System.Text.UTF8Encoding]::new($false))
                Write-AppLog "Vibe Kanban launch script written successfully" "DEBUG"

                $form.Hide()
                # Run the launch script
                Write-AppLog "Starting launch_vibe_kanban.ps1 process..." "INFO"
                Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$vibeScript`"" -WindowStyle Hidden
                Write-AppLog "Vibe Kanban launch process started successfully" "INFO"

                # Wait a moment, then close the main form
                Start-Sleep -Milliseconds 500
                Write-AppLog "Closing main form" "INFO"
                $form.Close()
            } else {
                Write-AppLog "ERROR: Failed to load Vibe Kanban launch script from embedded resources" "ERROR"
                [System.Windows.Forms.MessageBox]::Show("Error: Vibe Kanban launch script could not be loaded from embedded resources.`n`nCheck the log file for details:`n$script:LogFile", "Error", 'OK', 'Error')
                $form.Show()
            }
        } else {
            Write-AppLog "Container 'ai-cli' not found" "WARN"
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
        }
    } catch {
        Write-AppLog "ERROR: Exception in Launch Vibe Kanban: $($_.Exception.Message)" "ERROR"
        Write-AppLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while launching Vibe Kanban:`n`n$($_.Exception.Message)`n`nPlease check the log file for details:`n$script:LogFile",
            "Launch Error",
            'OK',
            'Error'
        )
        $form.Show()
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
        $dockerPath = $script:DockerDesktopPath
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

