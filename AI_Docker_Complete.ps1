# AI_Docker_Complete.ps1 - Complete self-contained installer
# This script contains all files embedded and will extract them on first run

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Get the directory where this exe/script is running from
$installDir = $null

# Try different methods to get the directory
if ($PSScriptRoot) {
    $installDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    # For compiled exe, try to get the assembly location
    try {
        $assemblyLocation = [System.Reflection.Assembly]::GetExecutingAssembly().Location
        if (-not [string]::IsNullOrEmpty($assemblyLocation)) {
            $installDir = [System.IO.Path]::GetDirectoryName($assemblyLocation)
        }
    } catch {
        # Silently continue if this fails
    }
}

# Final fallback to current directory
if ([string]::IsNullOrEmpty($installDir)) {
    $installDir = (Get-Location).Path
}

# Matrix Green Theme Colors
$script:MatrixGreen = [System.Drawing.Color]::FromArgb(0, 255, 65)
$script:MatrixDarkGreen = [System.Drawing.Color]::FromArgb(0, 20, 0)
$script:MatrixMidGreen = [System.Drawing.Color]::FromArgb(0, 40, 10)
$script:MatrixAccent = [System.Drawing.Color]::FromArgb(0, 180, 50)

# Function to extract embedded files
function Extract-EmbeddedFiles {
    Write-Host "Extracting embedded files to: $installDir" -ForegroundColor Green

    # Create files from embedded Base64 content
    $filesBase64 = @{
        'setup_wizard.ps1' = 'SETUP_WIZARD_PS1_BASE64_HERE'
        'launch_claude.ps1' = 'LAUNCH_CLAUDE_PS1_BASE64_HERE'
        'docker-compose.yml' = 'DOCKER_COMPOSE_YML_BASE64_HERE'
        'Dockerfile' = 'DOCKERFILE_BASE64_HERE'
        'entrypoint.sh' = 'ENTRYPOINT_SH_BASE64_HERE'
        'claude_wrapper.sh' = 'CLAUDE_WRAPPER_SH_BASE64_HERE'
        'fix_line_endings.ps1' = 'FIX_LINE_ENDINGS_PS1_BASE64_HERE'
        '.gitattributes' = '_GITATTRIBUTES_BASE64_HERE'
        'README.md' = 'README_MD_BASE64_HERE'
    }

    foreach ($fileName in $filesBase64.Keys) {
        $filePath = Join-Path $installDir $fileName
        $base64Content = $filesBase64[$fileName]

        # Decode Base64 to get original content
        $bytes = [System.Convert]::FromBase64String($base64Content)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)

        # Write file with UTF8 encoding
        [System.IO.File]::WriteAllText($filePath, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  Extracted: $fileName" -ForegroundColor Cyan
    }

    Write-Host "All files extracted successfully!" -ForegroundColor Green
}

# Check if files need to be extracted
$requiredFiles = @('setup_wizard.ps1', 'launch_claude.ps1', 'docker-compose.yml', 'Dockerfile')
$needsExtraction = $false
foreach ($file in $requiredFiles) {
    if (-not (Test-Path (Join-Path $installDir $file))) {
        $needsExtraction = $true
        break
    }
}

if ($needsExtraction) {
    Extract-EmbeddedFiles
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
$lblFooter.ForeColor = $script:MatrixGreen
$lblFooter.BackColor = 'Transparent'
$lblFooter.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblFooter)

# Description
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Left = 20; $lblDesc.Top = 120
$lblDesc.Width = 560; $lblDesc.Height = 60
$lblDesc.Text = "Select an option below to manage your AI Docker environment:`n`nFirst time? Run 'First Time Setup' to install everything.`nAlready setup? Use 'Launch Claude CLI' for daily access."
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
$lblSetupInfo.Text = "Installs Docker image and Claude CLI (5-10 minutes)"
$lblSetupInfo.ForeColor = $script:MatrixGreen
$lblSetupInfo.BackColor = 'Transparent'
$lblSetupInfo.Font = New-Object System.Drawing.Font('Consolas', 8)
$form.Controls.Add($lblSetupInfo)

# Button 2: Launch Claude
$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = "2. LAUNCH CLAUDE CLI"
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
    $setupScript = Join-Path $installDir "setup_wizard.ps1"
    if (Test-Path $setupScript) {
        $form.Hide()
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$setupScript`"" -Wait
        $form.Show()
        [System.Windows.Forms.MessageBox]::Show("Setup wizard completed. You can now use 'Launch Claude CLI' to access your workspace.", "Setup Complete", 'OK', 'Information')
    } else {
        [System.Windows.Forms.MessageBox]::Show("Error: setup_wizard.ps1 not found.`n`nPlease run the extraction again.", "File Not Found", 'OK', 'Error')
    }
})

$btnLaunch.Add_Click({
    $launchScript = Join-Path $installDir "launch_claude.ps1"
    if (Test-Path $launchScript) {
        # Check if .env exists
        $envFile = Join-Path $installDir ".env"
        if (-not (Test-Path $envFile)) {
            $result = [System.Windows.Forms.MessageBox]::Show("Setup has not been completed yet.`n`nWould you like to run the First Time Setup now?", "Setup Required", 'YesNo', 'Warning')
            if ($result -eq 'Yes') {
                $btnSetup.PerformClick()
            }
            return
        }

        $form.Hide()
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$launchScript`""
        Start-Sleep -Seconds 1
        $form.Close()
    } else {
        [System.Windows.Forms.MessageBox]::Show("Error: launch_claude.ps1 not found.`n`nPlease run the extraction again.", "File Not Found", 'OK', 'Error')
    }
})

$btnExit.Add_Click({
    $form.Close()
})

# Show form
[void]$form.ShowDialog()

