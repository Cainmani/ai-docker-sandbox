# launch_claude.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Matrix Green Theme Colors
$script:MatrixGreen = [System.Drawing.Color]::FromArgb(0, 255, 65)      # Bright Matrix Green
$script:MatrixDarkGreen = [System.Drawing.Color]::FromArgb(0, 20, 0)    # Very Dark Green Background
$script:MatrixMidGreen = [System.Drawing.Color]::FromArgb(0, 40, 10)    # Mid Dark Green
$script:MatrixAccent = [System.Drawing.Color]::FromArgb(0, 180, 50)     # Accent Green
$script:Arrow = [char]62 + [char]62                                      # >> symbol to avoid parser issues

function ShowMsg($text, $icon='Information') {
    [System.Windows.Forms.MessageBox]::Show($text, "AI CLI Launcher", 'OK', $icon) | Out-Null
}

function Find-Docker() {
    # Check if docker is in PATH
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCmd) {
        return $dockerCmd.Source
    }

    # Check common Docker Desktop installation paths
    $possiblePaths = @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe",
        "$env:ProgramW6432\Docker\Docker\resources\bin\docker.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function DockerOk() {
    try {
        $dockerPath = Find-Docker
        if (-not $dockerPath) {
            return $false
        }
        $p = Start-Process -FilePath $dockerPath -ArgumentList "info" -WindowStyle Hidden -PassThru -Wait
        return ($p.ExitCode -eq 0)
    } catch { return $false }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = ">>> AI CLI LAUNCHER :: MATRIX ACCESS <<<"
$form.Width = 560; $form.Height = 280
$form.BackColor = $script:MatrixDarkGreen
$form.ForeColor = $script:MatrixGreen
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Left=20; $lblHeader.Top=20; $lblHeader.Width=520; $lblHeader.Height=24
$lblHeader.Text = "============================================================"
$lblHeader.ForeColor=$script:MatrixGreen; $lblHeader.BackColor='Transparent'
$lblHeader.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Left=20; $lblTitle.Top=42; $lblTitle.Width=520; $lblTitle.Height=24
$lblTitle.Text = "      WORKSPACE SHELL ACCESS - DOCKER CONTAINER"
$lblTitle.ForeColor=$script:MatrixGreen; $lblTitle.BackColor='Transparent'
$lblTitle.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblTitle)

$lblFooter = New-Object System.Windows.Forms.Label
$lblFooter.Left=20; $lblFooter.Top=64; $lblFooter.Width=520; $lblFooter.Height=24
$lblFooter.Text = "============================================================"
$lblFooter.ForeColor=$script:MatrixGreen; $lblFooter.BackColor='Transparent'
$lblFooter.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblFooter)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Left=20; $lbl.Top=100; $lbl.Width=520; $lbl.Height=80
$workflowText = $script:Arrow + " Opens Ubuntu bash terminal at /workspace directory`n`n" + $script:Arrow + " Next steps: Create or navigate to project directory`n" + $script:Arrow + " Then run: claude (to start AI CLI)"
$lbl.Text = $workflowText
$lbl.ForeColor=$script:MatrixGreen; $lbl.BackColor='Transparent'
$lbl.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($lbl)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "Launch Workspace Shell"
$btnOpen.Left=320; $btnOpen.Top=190; $btnOpen.Width=200; $btnOpen.Height=40
$btnOpen.FlatStyle='Flat'
$btnOpen.FlatAppearance.BorderColor = $script:MatrixAccent
$btnOpen.FlatAppearance.BorderSize = 2
$btnOpen.BackColor=$script:MatrixMidGreen
$btnOpen.ForeColor=$script:MatrixGreen
$btnOpen.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnOpen)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Close"
$btnCancel.Left=200; $btnCancel.Top=190; $btnCancel.Width=100; $btnCancel.Height=40
$btnCancel.FlatStyle='Flat'
$btnCancel.FlatAppearance.BorderColor = $script:MatrixAccent
$btnCancel.FlatAppearance.BorderSize = 2
$btnCancel.BackColor=$script:MatrixMidGreen
$btnCancel.ForeColor=$script:MatrixGreen
$btnCancel.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnCancel)

$btnCancel.Add_Click({ $form.Close() })

$btnOpen.Add_Click({
    # First check if Docker executable exists
    $dockerPath = Find-Docker
    if (-not $dockerPath) {
        ShowMsg ("[ERROR] " + $script:Arrow + " Docker is not installed or cannot be found.`n`n" + $script:Arrow + " Please install Docker Desktop from:`nhttps://docs.docker.com/desktop/setup/install/windows-install/") 'Error'
        return
    }

    # Check if Docker is running
    if (-not (DockerOk)) {
        # Docker exists but not running - try to start Docker Desktop
        ShowMsg ("[INFO] " + $script:Arrow + " Docker Desktop is not running. Attempting to start...`n`nThis may take 30-60 seconds.") 'Information'

        # Try to start Docker Desktop
        $dockerDesktop = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerDesktop) {
            Start-Process $dockerDesktop

            # Wait for Docker to start (max 60 seconds)
            $waited = 0
            while ($waited -lt 60 -and -not (DockerOk)) {
                Start-Sleep -Seconds 2
                $waited += 2
            }

            if (-not (DockerOk)) {
                ShowMsg ("[ERROR] " + $script:Arrow + " Docker Desktop did not start in time.`n`n" + $script:Arrow + " Please start Docker Desktop manually and try again.") 'Warning'
                return
            }
        } else {
            ShowMsg ("[ERROR] " + $script:Arrow + " Docker Desktop is not running.`n`n" + $script:Arrow + " Please start Docker Desktop manually and try again.") 'Warning'
            return
        }
    }

    # Check if ai-cli container exists
    $containerCheck = & $dockerPath ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>&1
    if ($containerCheck -ne "ai-cli") {
        ShowMsg ("[ERROR] " + $script:Arrow + " The ai-cli container does not exist.`n`n" + $script:Arrow + " Please run the Setup Wizard first:`n`n    powershell -ExecutionPolicy Bypass -File setup_wizard.ps1`n`nThe wizard will build the Docker image and install Claude Code CLI.") 'Error'
        return
    }

    # Check if container is running, start if needed
    $containerStatus = & $dockerPath ps --filter "name=ai-cli" --format "{{.Names}}" 2>&1
    if ($containerStatus -ne "ai-cli") {
        Write-Host "Starting container ai-cli..." -ForegroundColor Green
        Start-Process -FilePath $dockerPath -ArgumentList "start","ai-cli" -WindowStyle Hidden -Wait | Out-Null
        Start-Sleep -Seconds 2
    }

    # Read username from .env file
    $envFile = Join-Path $PSScriptRoot ".env"
    $userName = "user"  # default
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile
        foreach ($line in $envContent) {
            if ($line -match '^USER_NAME=(.+)$') {
                $userName = $matches[1]
                break
            }
        }
    }


    # Build the docker exec command - connect as the user and start at /workspace
    $dockerCmd = "`"$dockerPath`" exec -it -u $userName -w /workspace ai-cli bash"

    # Open terminal at /workspace directory
    if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
        # Use Windows Terminal if available
        Start-Process wt.exe "cmd.exe /k $dockerCmd"
    } else {
        # Fallback to cmd - open new window with docker exec
        Start-Process cmd.exe "/k $dockerCmd"
    }

    # Wait a moment for the terminal to open, then close this launcher window
    Start-Sleep -Milliseconds 500
    $form.Close()
})

[void]$form.ShowDialog()
