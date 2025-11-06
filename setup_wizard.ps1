# setup_wizard.ps1
# Requirements: Windows PowerShell 5+ or PowerShell 7+, Docker Desktop installed
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------- automatic line ending fix ----------
function Fix-LineEndings {
    param([string]$scriptPath)

    $files = @('entrypoint.sh', 'setup.sh', 'claude_wrapper.sh')
    $fixed = $false

    foreach ($file in $files) {
        $filePath = Join-Path $scriptPath $file

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

# ---------- helpers ----------
# Matrix Green Theme Colors
$script:MatrixGreen = [System.Drawing.Color]::FromArgb(0, 255, 65)      # Bright Matrix Green
$script:MatrixDarkGreen = [System.Drawing.Color]::FromArgb(0, 20, 0)    # Very Dark Green Background
$script:MatrixMidGreen = [System.Drawing.Color]::FromArgb(0, 40, 10)    # Mid Dark Green
$script:MatrixAccent = [System.Drawing.Color]::FromArgb(0, 180, 50)     # Accent Green
$script:Arrow = [char]62 + [char]62                                      # >> symbol to avoid parser issues

function New-Label([string]$text, [int]$x, [int]$y, [int]$w=560, [int]$h=24, [int]$fontSize=10, [bool]$bold=$false, [bool]$center=$false) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.AutoSize = $false
    $lbl.Width = $w; $lbl.Height = $h
    $lbl.Left = $x; $lbl.Top = $y
    $lbl.ForeColor = $script:MatrixGreen
    $lbl.BackColor = 'Transparent'
    if ($center) {
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    }
    $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $lbl.Font = New-Object System.Drawing.Font('Consolas', $fontSize, $style)
    return $lbl
}
function New-Textbox([int]$x, [int]$y, [int]$w=560, [int]$h=28, [bool]$password=$false) {
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Left = $x; $tb.Top = $y
    $tb.Width = $w; $tb.Height = $h
    if ($password) { $tb.UseSystemPasswordChar = $true }
    $tb.BackColor = $script:MatrixMidGreen
    $tb.ForeColor = $script:MatrixGreen
    $tb.BorderStyle = 'FixedSingle'
    $tb.Font = New-Object System.Drawing.Font('Consolas', 10)
    return $tb
}
function New-Button([string]$text, [int]$x, [int]$y, [int]$w=120, [int]$h=34) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Left = $x; $btn.Top = $y
    $btn.Width = $w; $btn.Height = $h
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderColor = $script:MatrixAccent
    $btn.FlatAppearance.BorderSize = 2
    $btn.BackColor = $script:MatrixMidGreen
    $btn.ForeColor = $script:MatrixGreen
    $btn.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
    return $btn
}
function New-PanelPage() {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $script:MatrixDarkGreen
    return $p
}
function Show-Error([string]$msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, 'Setup', 'OK', 'Error') | Out-Null
}
function Show-Info([string]$msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, 'Setup', 'OK', 'Information') | Out-Null
}
$script:runningProcess = $null

function Run-Process-UI([string]$file, [string]$arguments, $progressBar, $statusLabel) {
    try {
        # Log command to console with proper variable expansion
        Write-Host '[' -NoNewline -ForegroundColor DarkGray
        Write-Host (Get-Date -Format 'HH:mm:ss') -NoNewline -ForegroundColor DarkGray
        Write-Host '] [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'EXEC' -NoNewline -ForegroundColor Magenta
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host "$file $arguments" -ForegroundColor White

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $file
        $psi.Arguments = $arguments
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()

        $script:runningProcess = $p

        # Initialize progress bar
        if ($progressBar) {
            $progressBar.Value = 0
            $progressBar.Style = 'Continuous'
            [System.Windows.Forms.Application]::DoEvents()
        }

        $lastDot = [DateTime]::Now
        $progressIncrement = 0

        while (-not $p.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()

            # Update progress bar - increment gradually
            if ($progressBar) {
                $progressIncrement += 2
                if ($progressIncrement -gt 95) { $progressIncrement = 95 } # Cap at 95% until complete
                $progressBar.Value = $progressIncrement
                [System.Windows.Forms.Application]::DoEvents()
            }

            # Show progress dots in console
            if (([DateTime]::Now - $lastDot).TotalSeconds -gt 1) {
                Write-Host '.' -NoNewline -ForegroundColor DarkGray
                $lastDot = [DateTime]::Now
            }

            Start-Sleep -Milliseconds 120
        }
        Write-Host '' # New line

        $script:runningProcess = $null

        # Complete the progress bar
        if ($progressBar) {
            $progressBar.Value = 100
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 300
            $progressBar.Value = 0
            [System.Windows.Forms.Application]::DoEvents()
        }

        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        if ($p.ExitCode -ne 0) {
            if ($statusLabel) { $statusLabel.Text = "Command failed (exit $($p.ExitCode))" }
            Write-Host '[ERROR] Exit code: ' -NoNewline -ForegroundColor Red
            Write-Host $p.ExitCode -ForegroundColor Red
            if ($err) {
                $errPreview = $err.Substring(0, [Math]::Min(200, $err.Length))
                Write-Host "  STDERR: $errPreview" -ForegroundColor Yellow
            }
            return @{ Ok = $false; StdOut = $out; StdErr = $err; Code = $p.ExitCode }
        } else {
            if ($statusLabel) { $statusLabel.Text = 'Command completed' }
            Write-Host '[OK] Completed' -ForegroundColor Green
            return @{ Ok = $true; StdOut = $out; StdErr = $err; Code = 0 }
        }
    } catch {
        Write-Host "[CRASH] $($_.Exception.Message)" -ForegroundColor Red
        return @{ Ok = $false; StdOut = ''; StdErr = $_.Exception.Message; Code = -1 }
    }
}
function Docker-Running() {
    try {
        $r = Run-Process-UI -file 'docker' -arguments 'info' -progressBar $null -statusLabel $null
        return $r.Ok
    } catch { return $false }
}

# ---------- state ----------
$state = [ordered]@{
    UserName = ''
    Password = ''
    ParentPath = ''
    WorkspacePath = ''
}
$composePath = Join-Path $PSScriptRoot 'docker-compose.yml'
if (-not (Test-Path $composePath)) {
    Show-Error ('docker-compose.yml not found in this folder.' + [Environment]::NewLine + 'Place setup_wizard.ps1 in the ai-docker folder.')
    return
}

# ---------- main form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = '>>> AI CLI DOCKER SETUP :: MATRIX PROTOCOL <<<'
$form.Width = 950
$form.Height = 700
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:MatrixDarkGreen
$form.ForeColor = $script:MatrixGreen
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# footer controls
$btnBack = New-Button 'Back' 630 580
$btnNext = New-Button 'Next' 760 580
$btnCancel = New-Button 'Cancel' 500 580
$form.Controls.AddRange(@($btnBack,$btnNext,$btnCancel))

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Left = 20; $progress.Top = 520
$progress.Width = 880; $progress.Height = 30
$progress.Style = 'Continuous'
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.ForeColor = $script:MatrixGreen
$progress.BackColor = [System.Drawing.Color]::Black  # Black background for better contrast
$form.Controls.Add($progress)

$status = New-Label '' 20 555 880 20 9
$form.Controls.Add($status)

# ---------- pages ----------
$pages = @()

# Page 0: Welcome
$p0 = New-PanelPage
$p0.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p0.Controls.Add((New-Label -text 'WELCOME TO AI CLI DOCKER SETUP - SECURE AI ENVIRONMENT WIZARD' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p0.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p0.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p0.Controls.Add((New-Label 'This wizard will help you set up a Docker container to run the AI Command Line' 20 95 880 24 10 $false $true))
$p0.Controls.Add((New-Label 'Interface (CLI) in a secure, isolated environment. This prevents the AI from' 20 115 880 24 10 $false $true))
$p0.Controls.Add((New-Label 'accessing files on your computer that it should not have access to.' 20 135 880 24 10 $false $true))
$p0.Controls.Add((New-Label '' 20 160 880 24 10 $false $true))
$p0.Controls.Add((New-Label 'The wizard will automatically:' 20 180 880 24 10 $true $true))
$p0.Controls.Add((New-Label '>> Create a secure AI_Work directory for all your AI projects' 20 205 880 24 10 $false $true))
$p0.Controls.Add((New-Label '>> Configure environment variables (USER_NAME, USER_PASSWORD, WORKSPACE_PATH)' 20 230 880 24 10 $false $true))
$p0.Controls.Add((New-Label '>> Build and deploy the Docker container' 20 255 880 24 10 $false $true))
$p0.Controls.Add((New-Label '>> Install Claude Code CLI inside the container' 20 280 880 24 10 $false $true))
$p0.Controls.Add((New-Label '' 20 305 880 24 10 $false $true))
$p0.Controls.Add((New-Label '⚠ NOTE: Do not move the AI_Work folder after setup - it will break the configuration' 20 330 880 24 10 $false $true))
$p0.Controls.Add((New-Label '' 20 355 880 24 10 $false $true))
$p0.Controls.Add((New-Label 'Click "Next" to begin the automatic setup process.' 20 380 880 24 10 $true $true))
$pages += $p0

# Page 1: Credentials
$p1 = New-PanelPage
$p1.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p1.Controls.Add((New-Label -text 'UBUNTU SYSTEM CREDENTIALS SETUP' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p1.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p1.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p1.Controls.Add((New-Label 'These credentials will be used for the Ubuntu system running inside the Docker container.' 20 95 880 24 10 $false $true))
$p1.Controls.Add((New-Label 'This is a secure Linux environment isolated from your Windows system.' 20 115 880 24 10 $false $true))
$p1.Controls.Add((New-Label '' 20 140 880 24 10 $false $true))
$p1.Controls.Add((New-Label 'Don''t know what a container is? Learn more at:' 20 160 880 24 9 $false $true))
$p1.Controls.Add((New-Label 'https://www.docker.com/resources/what-container/' 20 180 880 24 9 $false $true))
$p1.Controls.Add((New-Label '' 20 205 880 24 10 $false $true))
$p1.Controls.Add((New-Label 'Username:' 20 225 880 20 10 $true $false))
$script:tbUser = New-Textbox 20 245 400
$p1.Controls.Add($script:tbUser)
$p1.Controls.Add((New-Label 'Password:' 20 285 880 20 10 $true $false))
$script:tbPass = New-Textbox 20 305 400 28 $true
$p1.Controls.Add($script:tbPass)
$p1.Controls.Add((New-Label 'Confirm Password:' 20 345 880 20 10 $true $false))
$script:tbPassConfirm = New-Textbox 20 365 400 28 $true
$p1.Controls.Add($script:tbPassConfirm)
$p1.Controls.Add((New-Label '' 20 405 880 24 10 $false $true))
$p1.Controls.Add((New-Label 'Note: These credentials will be securely stored in the .env file.' 20 425 880 24 9 $false $true))
$pages += $p1

# Page 2: Folder choose
$p2 = New-PanelPage
$p2.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p2.Controls.Add((New-Label -text 'WORKSPACE DIRECTORY SELECTION' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p2.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p2.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p2.Controls.Add((New-Label 'Select the PARENT directory where your AI_Work folder will be created.' 20 95 880 24 10 $false $true))
$p2.Controls.Add((New-Label 'This will be the home of all your AI projects and work. You will be able to access' 20 115 880 24 10 $false $true))
$p2.Controls.Add((New-Label 'all the files that you and the AI create here.' 20 135 880 24 10 $false $true))
$p2.Controls.Add((New-Label '' 20 160 880 24 10 $false $true))
$p2.Controls.Add((New-Label 'Select Parent Directory:' 20 180 880 20 10 $true $true))
$script:tbParent = New-Textbox 20 200 700
$btnBrowse = New-Button 'Browse...' 730 200 130 30
$p2.Controls.Add($script:tbParent)
$p2.Controls.Add($btnBrowse)
$p2.Controls.Add((New-Label '' 20 235 880 24 10 $false $true))
$p2.Controls.Add((New-Label 'Example:' 20 260 880 24 9 $false $true))
$p2.Controls.Add((New-Label '>> If you select: C:\Users\YourName\Documents' 20 285 880 24 9 $false $true))
$p2.Controls.Add((New-Label '' 20 305 880 24 10 $false $true))
$p2.Controls.Add((New-Label '>> The wizard creates: C:\Users\YourName\Documents\AI_Work' 20 330 880 24 9 $false $true))
$p2.Controls.Add((New-Label '' 20 350 880 24 10 $false $true))
$p2.Controls.Add((New-Label '>> All your AI project data will be stored in AI_Work subdirectories' 20 375 880 24 9 $false $true))
$p2.Controls.Add((New-Label '' 20 395 880 24 10 $false $true))
$p2.Controls.Add((New-Label '>> You can access these files directly from Windows File Explorer' 20 420 880 24 9 $false $true))
$pages += $p2

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select the PARENT directory where AI_Work folder will be created'
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:tbParent.Text = $dlg.SelectedPath
    }
})

# Page 3: Docker check
$p3 = New-PanelPage
$p3.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p3.Controls.Add((New-Label -text 'DOCKER DESKTOP STATUS CHECK' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p3.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p3.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p3.Controls.Add((New-Label 'Docker Desktop must be installed and running to proceed with the setup.' 20 95 880 24 10 $false $true))
$p3.Controls.Add((New-Label '' 20 120 880 24 10 $false $true))
$script:lblDock = New-Label 'Checking Docker status...' 20 140 880 30 10 $true $true
$p3.Controls.Add($script:lblDock)
$p3.Controls.Add((New-Label '' 20 175 880 24 10 $false $true))
$btnRetryDock = New-Button 'Retry Check' 375 200 130 35
$p3.Controls.Add($btnRetryDock)
$p3.Controls.Add((New-Label '' 20 245 880 24 10 $false $true))
$p3.Controls.Add((New-Label 'If Docker is not installed or you are unsure:' 20 270 880 24 10 $true $true))
$p3.Controls.Add((New-Label '' 20 295 880 24 10 $false $true))
$p3.Controls.Add((New-Label '>> Download Docker Desktop from:' 20 320 880 24 9 $false $true))
$p3.Controls.Add((New-Label 'https://docs.docker.com/desktop/setup/install/windows-install/' 20 345 880 24 9 $false $true))
$p3.Controls.Add((New-Label '' 20 370 880 24 10 $false $true))
$p3.Controls.Add((New-Label '>> After installing, ensure Docker Desktop is running (check system tray)' 20 395 880 24 9 $false $true))
$p3.Controls.Add((New-Label '' 20 420 880 24 10 $false $true))
$p3.Controls.Add((New-Label '>> Then click "Retry Check" to verify it''s running' 20 445 880 24 9 $false $true))
$pages += $p3

$btnRetryDock.Add_Click({
    $script:lblDock.Text = 'Checking Docker status...'
    [System.Windows.Forms.Application]::DoEvents()
    if (Docker-Running) {
        $script:lblDock.Text = '✓ Docker is running! Click "Next" to continue.'
        $script:lblDock.ForeColor = $script:MatrixGreen
    } else {
        $script:lblDock.Text = '✗ Docker is not running. Please start Docker Desktop and retry.'
        $script:lblDock.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
    }
})

# Page 4: Build/Up
$p4 = New-PanelPage
$p4.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p4.Controls.Add((New-Label -text 'BUILDING AND DEPLOYING CONTAINER' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p4.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p4.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p4.Controls.Add((New-Label 'The wizard is now building the Docker image and deploying the container.' 20 95 880 24 10 $false $true))
$p4.Controls.Add((New-Label 'This process downloads Ubuntu and installs all necessary packages.' 20 115 880 24 10 $false $true))
$p4.Controls.Add((New-Label '' 20 140 880 24 10 $false $true))
$p4.Controls.Add((New-Label 'First deployment may take 2-5 minutes.' 20 160 880 24 10 $true $true))
$p4.Controls.Add((New-Label 'Watch the progress bar and console for detailed updates.' 20 180 880 24 10 $true $true))
$p4.Controls.Add((New-Label '' 20 205 880 24 10 $false $true))
$p4.Controls.Add((New-Label 'Please wait while the setup completes...' 20 225 880 30 11 $true $true))
$pages += $p4

# Page 5: Install Claude
$p5 = New-PanelPage
$p5.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p5.Controls.Add((New-Label -text 'INSTALLING CLAUDE CODE CLI' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p5.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p5.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p5.Controls.Add((New-Label 'Installing Claude Code CLI via npm package manager...' 20 95 880 24 10 $false $true))
$p5.Controls.Add((New-Label 'Command: npm install -g @anthropic-ai/claude-code' 20 115 880 24 10 $false $true))
$p5.Controls.Add((New-Label '' 20 140 880 24 10 $false $true))
$p5.Controls.Add((New-Label 'Configuring global "claude" command wrapper...' 20 160 880 24 10 $false $true))
$p5.Controls.Add((New-Label '' 20 185 880 24 10 $false $true))
$p5.Controls.Add((New-Label 'This may take 1-2 minutes.' 20 205 880 24 10 $true $true))
$p5.Controls.Add((New-Label '' 20 230 880 24 10 $false $true))
$p5.Controls.Add((New-Label 'Watch the progress bar below for status...' 20 250 880 30 11 $true $true))
$pages += $p5

# Page 6: Done
$p6 = New-PanelPage
$p6.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p6.Controls.Add((New-Label -text 'SETUP COMPLETE - YOUR AI ENVIRONMENT IS READY!' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p6.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p6.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p6.Controls.Add((New-Label '✓ AI CLI Docker environment successfully initialized!' 20 95 880 24 10 $true $true))
$p6.Controls.Add((New-Label '' 20 120 880 24 10 $false $true))
$p6.Controls.Add((New-Label 'You can now use the launcher script to access your workspace shell.' 20 140 880 24 10 $false $true))
$p6.Controls.Add((New-Label '' 20 165 880 24 10 $false $true))
$p6.Controls.Add((New-Label 'Basic Workflow:' 20 190 880 24 10 $true $true))
$p6.Controls.Add((New-Label '' 20 215 880 24 10 $false $true))
$p6.Controls.Add((New-Label '1. Open a terminal and run: docker exec -it ai-cli bash' 20 240 880 24 9 $false $true))
$p6.Controls.Add((New-Label '' 20 260 880 24 10 $false $true))
$p6.Controls.Add((New-Label '2. Navigate to your project: cd /workspace/<your-project>' 20 285 880 24 9 $false $true))
$p6.Controls.Add((New-Label '' 20 305 880 24 10 $false $true))
$p6.Controls.Add((New-Label '3. Run Claude: claude' 20 330 880 24 9 $false $true))
$p6.Controls.Add((New-Label '' 20 350 880 24 10 $false $true))
$p6.Controls.Add((New-Label 'Key Points:' 20 375 880 24 10 $true $true))
$p6.Controls.Add((New-Label '' 20 395 880 24 10 $false $true))
$p6.Controls.Add((New-Label '>> Each subdirectory in AI_Work = isolated AI project context' 20 420 880 24 9 $false $true))
$p6.Controls.Add((New-Label '' 20 440 880 24 10 $false $true))
$p6.Controls.Add((New-Label '>> All data persists locally in your AI_Work folder on Windows' 20 465 880 24 9 $false $true))
$pages += $p6

# ---------- page plumbing ----------
$form.Controls.Add($pages[0])
$script:current = 0
$btnBack.Enabled = $false
function Show-Page([int]$i) {
    foreach ($p in $pages) { if ($form.Controls.Contains($p)) { $form.Controls.Remove($p) } }
    $form.Controls.Add($pages[$i])
    $btnBack.Enabled = ($i -gt 0)
    if ($i -eq $pages.Count-1) { $btnNext.Text = 'Finish' } else { $btnNext.Text = 'Next' }
}
$btnCancel.Add_Click({
    Write-Host '[WARNING] User cancelled - cleaning up...' -ForegroundColor Yellow

    # Kill any running process
    if ($script:runningProcess -and -not $script:runningProcess.HasExited) {
        Write-Host '[INFO] Terminating running process...' -ForegroundColor Cyan
        try {
            $script:runningProcess.Kill()
            $script:runningProcess.WaitForExit(2000)
            Write-Host '[INFO] Process terminated' -ForegroundColor Green
        } catch {
            Write-Host '[WARNING] Could not kill process: $($_.Exception.Message)' -ForegroundColor Yellow
        }
    }

    $form.Close()
})
$btnBack.Add_Click({
    if ($script:current -gt 0) {
        Write-Host "[DEBUG] Back button clicked - going from page $script:current to $($script:current - 1)" -ForegroundColor Yellow
        $script:current--
        Show-Page $script:current
    }
})

# ---------- next button logic ----------
$btnNext.Add_Click({
    Write-Host "[DEBUG] Next button clicked. Current page: $script:current" -ForegroundColor Cyan
    switch ($script:current) {
        0 {
            Write-Host "[DEBUG] Page 0: Welcome -> advancing" -ForegroundColor Cyan
            $script:current++; Show-Page $script:current
        }
        1 {
            Write-Host "[DEBUG] Page 1: Credentials validation" -ForegroundColor Cyan
            Write-Host "[DEBUG] Username: '$($script:tbUser.Text)'" -ForegroundColor Yellow

            if ([string]::IsNullOrWhiteSpace($script:tbUser.Text) -or [string]::IsNullOrWhiteSpace($script:tbPass.Text) -or [string]::IsNullOrWhiteSpace($script:tbPassConfirm.Text)) {
                Write-Host "[ERROR] Validation failed - empty fields" -ForegroundColor Red
                Show-Error 'Please enter username, password, and confirm password'
                return
            }

            if ($script:tbPass.Text -ne $script:tbPassConfirm.Text) {
                Write-Host "[ERROR] Passwords do not match" -ForegroundColor Red
                Show-Error 'Passwords do not match. Please re-enter your password.'
                return
            }

            Write-Host "[SUCCESS] Credentials validated - advancing" -ForegroundColor Green
            $state.UserName = $script:tbUser.Text
            $state.Password = $script:tbPass.Text
            $script:current++; Show-Page $script:current
        }
        2 {
            Write-Host "[DEBUG] Page 2: Folder selection" -ForegroundColor Cyan
            if ([string]::IsNullOrWhiteSpace($script:tbParent.Text)) {
                Write-Host "[ERROR] No folder selected" -ForegroundColor Red
                Show-Error 'choose a parent folder'
                return
            }
            $state.ParentPath = $script:tbParent.Text
            $state.WorkspacePath = Join-Path $state.ParentPath 'AI_Work'
            Write-Host "[INFO] Creating workspace at: $($state.WorkspacePath)" -ForegroundColor Cyan

            if (-not (Test-Path $state.WorkspacePath)) {
                try {
                    New-Item -ItemType Directory -Path $state.WorkspacePath | Out-Null
                    Write-Host "[SUCCESS] AI_Work directory created" -ForegroundColor Green
                }
                catch {
                    $errMsg = "could not create $($state.WorkspacePath) - $($_.Exception.Message)"
                    Write-Host "[ERROR] $errMsg" -ForegroundColor Red
                    Show-Error $errMsg
                    return
                }
            } else {
                Write-Host "[INFO] AI_Work directory already exists" -ForegroundColor Yellow
            }

            # write .env
            Write-Host "[INFO] Creating .env file" -ForegroundColor Cyan
            $envPath = Join-Path $PSScriptRoot '.env'
            $nl = [Environment]::NewLine
            $envContent = "USER_NAME=$($state.UserName)" + $nl + "USER_PASSWORD=$($state.Password)" + $nl + "WORKSPACE_PATH=$($state.WorkspacePath)" + $nl
            $envContent | Out-File $envPath -Encoding UTF8
            $status.Text = ".env created at $envPath"
            Write-Host "[SUCCESS] .env file created" -ForegroundColor Green

            $script:current++; Show-Page $script:current

            Write-Host "[INFO] Checking Docker status..." -ForegroundColor Cyan
            if (Docker-Running) {
                Write-Host "[SUCCESS] Docker is running" -ForegroundColor Green
                $script:lblDock.Text = '[OK] ' + $script:Arrow + ' Docker is running. Click Next to continue.'
            } else {
                Write-Host "[WARNING] Docker not running" -ForegroundColor Yellow
                $script:lblDock.Text = '[ERROR] ' + $script:Arrow + ' Docker not running. Start Docker Desktop, then Retry.'
            }
        }
        3 {
            Write-Host "[DEBUG] Page 3: Docker check" -ForegroundColor Cyan
            if (-not (Docker-Running)) {
                Write-Host "[ERROR] Docker is not running" -ForegroundColor Red
                Show-Error 'docker is not running. open Docker Desktop, then click Retry.'
                return
            }
            Write-Host "[SUCCESS] Docker verified - proceeding to build" -ForegroundColor Green
            $script:current++; Show-Page $script:current

            # docker compose build
            $status.Text = 'docker compose build - may take 2 to 5 minutes first time'
            Write-Host "[INFO] Building Docker image - this downloads Ubuntu and installs packages" -ForegroundColor Cyan
            $buildArgs = 'compose -f "' + $composePath + '" build'
            $r1 = Run-Process-UI -file 'docker' -arguments $buildArgs -progressBar $progress -statusLabel $status
            if (-not $r1.Ok) {
                $errMsg = 'build failed' + [Environment]::NewLine + $r1.StdErr
                Write-Host "[ERROR] Docker build failed" -ForegroundColor Red
                Show-Error $errMsg
                return
            }
            Write-Host "[SUCCESS] Docker image built" -ForegroundColor Green

            # docker compose up -d
            $status.Text = 'docker compose up -d...'
            Write-Host "[INFO] Starting container" -ForegroundColor Cyan
            $upArgs = 'compose -f "' + $composePath + '" up -d'
            $r2 = Run-Process-UI -file 'docker' -arguments $upArgs -progressBar $progress -statusLabel $status
            if (-not $r2.Ok) {
                $errMsg = 'up failed' + [Environment]::NewLine + $r2.StdErr
                Write-Host "[ERROR] Container startup failed" -ForegroundColor Red
                Show-Error $errMsg
                return
            }
            Write-Host "[SUCCESS] Container started" -ForegroundColor Green

            # Wait for container to fully initialize
            $status.Text = 'Waiting for container to initialize...'
            Write-Host "[INFO] Waiting 5 seconds for container to fully initialize..." -ForegroundColor Cyan
            Start-Sleep -Seconds 5

            # Verify container is actually running
            Write-Host "[INFO] Verifying container status..." -ForegroundColor Cyan
            $checkRunning = Run-Process-UI -file 'docker' -arguments 'ps --filter "name=ai-cli" --format "{{.Status}}"' -progressBar $null -statusLabel $null
            if ($checkRunning.Ok -and $checkRunning.StdOut -match 'Up') {
                Write-Host "[SUCCESS] Container is running" -ForegroundColor Green
            } else {
                Write-Host "[ERROR] Container is not running!" -ForegroundColor Red
                Write-Host "[INFO] Checking container logs..." -ForegroundColor Yellow
                $logs = Run-Process-UI -file 'docker' -arguments 'logs ai-cli' -progressBar $null -statusLabel $null
                Write-Host "[LOGS] Container output:" -ForegroundColor Yellow
                Write-Host $logs.StdOut -ForegroundColor Gray
                Show-Error "Container failed to stay running. Check console for logs."
                return
            }
            Write-Host "[SUCCESS] Container ready" -ForegroundColor Green

            $status.Text = 'container started'
            # move to install page
            $script:current++; Show-Page $script:current

            # install AI CLI and create wrapper
            $status.Text = 'installing AI CLI...'

            # Step 1: Install claude-code via npm
            $status.Text = 'Installing Claude Code CLI - may take 1 to 2 minutes'
            Write-Host "[INFO] Installing npm package @anthropic-ai/claude-code" -ForegroundColor Cyan
            Write-Host "[INFO] This will download packages from npm registry..." -ForegroundColor Yellow
            $r3a = Run-Process-UI -file 'docker' -arguments 'exec ai-cli npm install -g @anthropic-ai/claude-code' -progressBar $progress -statusLabel $status
            if (-not $r3a.Ok) {
                $errMsg = 'npm install failed' + [Environment]::NewLine + $r3a.StdErr
                Write-Host "[ERROR] npm install failed" -ForegroundColor Red
                Write-Host "[ERROR] Exit code: $($r3a.Code)" -ForegroundColor Red
                Write-Host "[ERROR] Error details:" -ForegroundColor Red
                Write-Host $r3a.StdErr -ForegroundColor Yellow
                Show-Error $errMsg
                return
            }
            Write-Host "[SUCCESS] Claude Code CLI installed" -ForegroundColor Green

            # Step 2: Copy wrapper script into container
            $status.Text = 'installing wrapper script...'
            Write-Host "[INFO] Installing wrapper script" -ForegroundColor Cyan
            $wrapperPath = Join-Path $PSScriptRoot 'claude_wrapper.sh'
            $dq = [char]34
            $dockerCpArgs = 'cp ' + $dq + $wrapperPath + $dq + ' ai-cli:/tmp/claude'
            $r3b = Run-Process-UI -file 'docker' -arguments $dockerCpArgs -progressBar $progress -statusLabel $status

            # Step 3: Move to bin and make executable
            Write-Host "[INFO] Making wrapper executable" -ForegroundColor Cyan
            $r3c = Run-Process-UI -file 'docker' -arguments 'exec ai-cli sudo mv /tmp/claude /usr/local/bin/claude' -progressBar $progress -statusLabel $status
            $r3d = Run-Process-UI -file 'docker' -arguments 'exec ai-cli sudo chmod +x /usr/local/bin/claude' -progressBar $progress -statusLabel $status

            Write-Host '[SUCCESS] Installation complete!' -ForegroundColor Green
            $status.Text = 'system ready'
            $script:current++; Show-Page $script:current
        }
        6 {
            Write-Host "[INFO] User clicked Finish - closing wizard" -ForegroundColor Green
            $form.Close()
        }
    }
})

# Display startup banner
Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "    AI CLI DOCKER SETUP :: MATRIX PROTOCOL v1.0                " -ForegroundColor Green
Write-Host "    [SYSTEM ONLINE] Running automatic pre-flight checks        " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

# Automatic pre-flight checks
Write-Host "[PRE-FLIGHT] Running automatic system checks..." -ForegroundColor Cyan
Write-Host ""

# 1. Fix line endings automatically
Write-Host "[CHECK 1/3] Checking shell script line endings..." -ForegroundColor Cyan
$lineEndingsFixed = Fix-LineEndings -scriptPath $PSScriptRoot
if ($lineEndingsFixed) {
    Write-Host "[AUTO-FIX] Shell scripts converted to Unix format" -ForegroundColor Green
    Write-Host "[INFO] Docker image will be rebuilt automatically" -ForegroundColor Yellow
} else {
    Write-Host "[OK] Shell scripts already have correct line endings" -ForegroundColor Green
}
Write-Host ""

# 2. Check if old container exists and clean it up
Write-Host "[CHECK 2/3] Checking for existing containers..." -ForegroundColor Cyan
$existingContainer = docker ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>$null
if ($existingContainer -eq "ai-cli") {
    Write-Host "[INFO] Found existing ai-cli container" -ForegroundColor Yellow
    Write-Host "[AUTO-FIX] Removing old container for fresh start..." -ForegroundColor Yellow
    docker stop ai-cli 2>$null | Out-Null
    docker rm ai-cli 2>$null | Out-Null
    Write-Host "[SUCCESS] Old container removed" -ForegroundColor Green
} else {
    Write-Host "[OK] No existing container found" -ForegroundColor Green
}
Write-Host ""

# 3. If line endings were fixed, remove old image to force rebuild
if ($lineEndingsFixed) {
    Write-Host "[CHECK 3/3] Removing old Docker image..." -ForegroundColor Cyan
    $existingImage = docker images -q ai-docker-ai 2>$null
    if ($existingImage) {
        Write-Host "[AUTO-FIX] Removing old image to ensure fresh build..." -ForegroundColor Yellow
        docker rmi ai-docker-ai 2>$null | Out-Null
        Write-Host "[SUCCESS] Old image removed - will rebuild with fixed scripts" -ForegroundColor Green
    }
} else {
    Write-Host "[CHECK 3/3] Docker image status..." -ForegroundColor Cyan
    Write-Host "[OK] No rebuild needed" -ForegroundColor Green
}
Write-Host ""

Write-Host "================================================================" -ForegroundColor Green
Write-Host "[PRE-FLIGHT] All automatic checks complete!                   " -ForegroundColor Green
Write-Host "[READY] Starting wizard GUI...                                " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host ">>> Watch this console for detailed progress updates <<<" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INIT] Wizard starting..." -ForegroundColor Green
Write-Host "[INIT] Creating GUI form..." -ForegroundColor Cyan

Show-Page 0
Write-Host "[INIT] Displaying page 0 (Welcome)" -ForegroundColor Green
[void]$form.ShowDialog()
Write-Host ""
Write-Host "[SHUTDOWN] Wizard closed" -ForegroundColor Yellow

