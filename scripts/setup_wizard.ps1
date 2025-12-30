# setup_wizard.ps1
# Requirements: Windows PowerShell 5+ or PowerShell 7+, Docker Desktop installed
param([switch]$DevMode)

# ============================================================
# EARLY STARTUP LOGGING - Shows progress immediately
# ============================================================
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SETUP WIZARD STARTING..." -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INIT] Loading .NET assemblies..." -ForegroundColor Yellow

Add-Type -AssemblyName System.Windows.Forms
Write-Host "[INIT] System.Windows.Forms loaded" -ForegroundColor Green
Add-Type -AssemblyName System.Drawing
Write-Host "[INIT] System.Drawing loaded" -ForegroundColor Green

$script:IsDevMode = $DevMode.IsPresent
Write-Host "[INIT] DevMode: $($script:IsDevMode)" -ForegroundColor Cyan

# Show DEV MODE status at startup
if ($script:IsDevMode) {
    Write-Host "" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "   DEV MODE ACTIVE - UI TESTING MODE   " -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "  • Container will NOT be deleted" -ForegroundColor Magenta
    Write-Host "  • All popups will be skipped" -ForegroundColor Magenta
    Write-Host "  • Fast UI/UX testing enabled" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "" -ForegroundColor Magenta
}

# ---------- automatic line ending fix ----------
function Fix-LineEndings {
    param([string]$scriptPath)

    # Docker files location - detect if running from embedded exe or project directory
    $dockerPath = if ($scriptPath -like '*AI-Docker-CLI*docker-files*') {
        # Running from embedded exe - docker files are in same folder
        $scriptPath
    } else {
        # Running from project directory - docker files are in ../docker
        Join-Path $scriptPath '..\docker'
    }
    $files = @('entrypoint.sh', 'setup.sh', 'claude_wrapper.sh')
    $fixed = $false

    foreach ($file in $files) {
        $filePath = Join-Path $dockerPath $file

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
function New-LinkLabel([string]$url, [int]$x, [int]$y, [int]$w=880, [int]$h=24, [int]$fontSize=9, [bool]$center=$true) {
    $link = New-Object System.Windows.Forms.LinkLabel
    $link.Text = $url
    $link.Left = $x; $link.Top = $y
    $link.Width = $w; $link.Height = $h
    $link.LinkColor = $script:MatrixAccent
    $link.ActiveLinkColor = $script:MatrixGreen
    $link.VisitedLinkColor = $script:MatrixAccent
    $link.BackColor = 'Transparent'
    $link.Font = New-Object System.Drawing.Font('Consolas', $fontSize)
    if ($center) {
        $link.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    }
    $link.Add_LinkClicked({
        param($sender, $e)
        Start-Process $sender.Text
    })
    return $link
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

# Function to validate npm is working correctly (prevents "Unknown command: pm" errors)
# NOTE: Parallel implementation exists in docker/install_cli_tools.sh (validate_npm)
#       for the Linux container. Keep both in sync when making changes.
function Test-NpmFunctional {
    Write-Host "[INFO] Validating npm installation..." -ForegroundColor Cyan

    # Check if npm command exists
    $npmPath = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmPath) {
        Write-Host "[ERROR] npm not found in PATH" -ForegroundColor Red
        return @{ Valid = $false; Error = "npm not found in PATH"; NeedsInstall = $true }
    }

    # Verify npm can actually execute (catches "Unknown command: pm" type errors)
    try {
        $npmVersion = & npm --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] npm --version failed: $npmVersion" -ForegroundColor Red
            return @{ Valid = $false; Error = "npm not functioning: $npmVersion"; NeedsRepair = $true }
        }
    } catch {
        Write-Host "[ERROR] npm execution failed: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Valid = $false; Error = $_.Exception.Message; NeedsRepair = $true }
    }

    # Test npm can list global packages
    try {
        $listResult = & npm list -g --depth=0 2>&1
        if ($LASTEXITCODE -ne 0 -and $listResult -notmatch "empty") {
            Write-Host "[WARNING] npm global list had issues, but may still work" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[WARNING] Could not list npm global packages" -ForegroundColor Yellow
    }

    Write-Host "[OK] npm is functional (version: $npmVersion)" -ForegroundColor Green
    return @{ Valid = $true; Version = $npmVersion; Path = $npmPath.Source }
}

# Function to attempt npm repair
# NOTE: Parallel implementation exists in docker/install_cli_tools.sh (repair_npm)
function Repair-NpmInstallation {
    Write-Host "[INFO] Attempting to repair npm installation..." -ForegroundColor Yellow

    # Refresh PATH from system
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    # Clear npm cache
    try {
        & npm cache clean --force 2>&1 | Out-Null
        Write-Host "[INFO] npm cache cleared" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARNING] Could not clear npm cache" -ForegroundColor Yellow
    }

    # Re-test npm
    return Test-NpmFunctional
}

$script:runningProcess = $null

function Run-Process-UI([string]$file, [string]$arguments, $progressBar, $statusLabel, [string]$workingDirectory = '') {
    try {
        # Log command to console with proper variable expansion
        Write-Host '[' -NoNewline -ForegroundColor DarkGray
        Write-Host (Get-Date -Format 'HH:mm:ss') -NoNewline -ForegroundColor DarkGray
        Write-Host '] [' -NoNewline -ForegroundColor DarkGray
        Write-Host 'EXEC' -NoNewline -ForegroundColor Magenta
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host "$file $arguments" -ForegroundColor White
        if ($workingDirectory) {
            Write-Host "  Working Directory: $workingDirectory" -ForegroundColor DarkGray
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $file
        $psi.Arguments = $arguments
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        # Set working directory if provided
        if ($workingDirectory -and (Test-Path $workingDirectory)) {
            $psi.WorkingDirectory = $workingDirectory
        }

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi

        # Set up async output reading to prevent buffer deadlock
        $outputBuilder = New-Object System.Text.StringBuilder
        $errorBuilder = New-Object System.Text.StringBuilder

        $outputHandler = {
            if ($EventArgs.Data -ne $null) {
                [void]$Event.MessageData.AppendLine($EventArgs.Data)
            }
        }

        $errorHandler = {
            if ($EventArgs.Data -ne $null) {
                [void]$Event.MessageData.AppendLine($EventArgs.Data)
            }
        }

        $outputEvent = Register-ObjectEvent -InputObject $p -EventName OutputDataReceived -Action $outputHandler -MessageData $outputBuilder
        $errorEvent = Register-ObjectEvent -InputObject $p -EventName ErrorDataReceived -Action $errorHandler -MessageData $errorBuilder

        [void]$p.Start()

        # Begin async reading - this prevents buffer deadlock
        $p.BeginOutputReadLine()
        $p.BeginErrorReadLine()

        $script:runningProcess = $p

        # Initialize progress bar
        if ($progressBar) {
            $progressBar.Value = 0
            $progressBar.Style = 'Continuous'
            [System.Windows.Forms.Application]::DoEvents()
        }

        $lastDot = [DateTime]::Now
        $lastProgressUpdate = [DateTime]::Now
        $progressIncrement = 0

        # Optimized polling loop to reduce overhead for long-running processes like Docker builds
        # Changes: Longer sleep (250ms vs 120ms), less frequent progress updates (500ms), less console I/O (2s vs 1s)
        # This significantly improves performance for Docker Compose build operations
        while (-not $p.HasExited) {
            # Process Windows messages less frequently to reduce overhead
            [System.Windows.Forms.Application]::DoEvents()

            $now = [DateTime]::Now

            # Update progress bar every 500ms instead of every loop iteration
            if ($progressBar -and ($now - $lastProgressUpdate).TotalMilliseconds -gt 500) {
                $progressIncrement += 2
                if ($progressIncrement -gt 95) { $progressIncrement = 95 } # Cap at 95% until complete
                $progressBar.Value = $progressIncrement
                $lastProgressUpdate = $now
            }

            # Show progress dots every 2 seconds (reduced console I/O)
            if (($now - $lastDot).TotalSeconds -gt 2) {
                Write-Host '.' -NoNewline -ForegroundColor DarkGray
                $lastDot = $now
            }

            # Longer sleep interval reduces CPU usage and polling overhead
            Start-Sleep -Milliseconds 250
        }
        Write-Host '' # New line

        $script:runningProcess = $null

        # Wait for async readers to finish
        $p.WaitForExit()

        # Cleanup event handlers
        Unregister-Event -SourceIdentifier $outputEvent.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $errorEvent.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $outputEvent.Id -Force -ErrorAction SilentlyContinue
        Remove-Job -Id $errorEvent.Id -Force -ErrorAction SilentlyContinue

        # Complete the progress bar
        if ($progressBar) {
            $progressBar.Value = 100
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 300
            $progressBar.Value = 0
            [System.Windows.Forms.Application]::DoEvents()
        }

        $out = $outputBuilder.ToString()
        $err = $errorBuilder.ToString()

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

# Run a process with live output streaming to a terminal box (RichTextBox)
# This provides real-time feedback to the user during long-running operations like Docker builds
function Run-Process-WithTerminal {
    param(
        [string]$file,
        [string]$arguments,
        $terminalBox,
        $statusLabel,
        [string]$workingDirectory = '',
        [string]$operationName = 'Running'
    )

    try {
        # Log command start
        $timestamp = Get-Date -Format 'HH:mm:ss'
        Write-Host "[$timestamp] [EXEC] $file $arguments" -ForegroundColor White

        # Add to terminal box
        if ($terminalBox) {
            $terminalBox.AppendText(">> [$timestamp] $operationName...`r`n")
            $terminalBox.AppendText(">> Command: $file $arguments`r`n")
            $terminalBox.AppendText("`r`n")
            $terminalBox.SelectionStart = $terminalBox.TextLength
            $terminalBox.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $file
        $psi.Arguments = $arguments
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        if ($workingDirectory -and (Test-Path $workingDirectory)) {
            $psi.WorkingDirectory = $workingDirectory
        }

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi

        # Output collection
        $outputBuilder = New-Object System.Text.StringBuilder
        $errorBuilder = New-Object System.Text.StringBuilder

        # Create a synchronized queue for thread-safe output collection
        $outputQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

        # Event handlers that add lines to the queue
        $outputHandler = {
            if ($EventArgs.Data -ne $null) {
                [void]$Event.MessageData.OutputBuilder.AppendLine($EventArgs.Data)
                [void]$Event.MessageData.Queue.Enqueue($EventArgs.Data)
            }
        }

        $errorHandler = {
            if ($EventArgs.Data -ne $null) {
                [void]$Event.MessageData.ErrorBuilder.AppendLine($EventArgs.Data)
                [void]$Event.MessageData.Queue.Enqueue("[stderr] " + $EventArgs.Data)
            }
        }

        # Create message data object to pass to event handlers
        $messageData = @{
            OutputBuilder = $outputBuilder
            ErrorBuilder = $errorBuilder
            Queue = $outputQueue
        }

        $outputEvent = Register-ObjectEvent -InputObject $p -EventName OutputDataReceived -Action $outputHandler -MessageData $messageData
        $errorEvent = Register-ObjectEvent -InputObject $p -EventName ErrorDataReceived -Action $errorHandler -MessageData $messageData

        [void]$p.Start()
        $p.BeginOutputReadLine()
        $p.BeginErrorReadLine()

        $script:runningProcess = $p

        # Update status
        if ($statusLabel) {
            $statusLabel.Text = "$operationName in progress..."
            [System.Windows.Forms.Application]::DoEvents()
        }

        $lastTerminalUpdate = [DateTime]::Now
        $lineCount = 0

        # Polling loop with live terminal updates
        while (-not $p.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()

            # Dequeue and display new output lines
            $line = $null
            while ($outputQueue.TryDequeue([ref]$line)) {
                if ($line -and $line.Trim()) {
                    # Strip ANSI escape codes
                    $cleanLine = $line -replace '\x1b\[[0-9;]*m', '' -replace '\x1b\[K', ''

                    if ($terminalBox) {
                        $terminalBox.AppendText("$cleanLine`r`n")
                        $lineCount++

                        # Auto-scroll every few lines to reduce flickering
                        if ($lineCount % 3 -eq 0) {
                            $terminalBox.SelectionStart = $terminalBox.TextLength
                            $terminalBox.ScrollToCaret()
                        }
                    }

                    # Also show in console
                    Write-Host "  $cleanLine" -ForegroundColor DarkGray
                }
            }

            # Force UI update every 200ms
            $now = [DateTime]::Now
            if (($now - $lastTerminalUpdate).TotalMilliseconds -gt 200) {
                if ($terminalBox) {
                    $terminalBox.SelectionStart = $terminalBox.TextLength
                    $terminalBox.ScrollToCaret()
                }
                [System.Windows.Forms.Application]::DoEvents()
                $lastTerminalUpdate = $now
            }

            Start-Sleep -Milliseconds 100
        }

        # Process any remaining output
        Start-Sleep -Milliseconds 200
        $line = $null
        while ($outputQueue.TryDequeue([ref]$line)) {
            if ($line -and $line.Trim()) {
                $cleanLine = $line -replace '\x1b\[[0-9;]*m', '' -replace '\x1b\[K', ''
                if ($terminalBox) {
                    $terminalBox.AppendText("$cleanLine`r`n")
                }
            }
        }

        $script:runningProcess = $null
        $p.WaitForExit()

        # Cleanup event handlers
        Unregister-Event -SourceIdentifier $outputEvent.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $errorEvent.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $outputEvent.Id -Force -ErrorAction SilentlyContinue
        Remove-Job -Id $errorEvent.Id -Force -ErrorAction SilentlyContinue

        $out = $outputBuilder.ToString()
        $err = $errorBuilder.ToString()

        # Final terminal update
        if ($terminalBox) {
            $terminalBox.AppendText("`r`n")
            if ($p.ExitCode -eq 0) {
                $terminalBox.AppendText(">> [$operationName] Completed successfully`r`n")
            } else {
                $terminalBox.AppendText(">> [$operationName] Failed with exit code $($p.ExitCode)`r`n")
            }
            $terminalBox.SelectionStart = $terminalBox.TextLength
            $terminalBox.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($p.ExitCode -ne 0) {
            if ($statusLabel) { $statusLabel.Text = "$operationName failed (exit $($p.ExitCode))" }
            Write-Host "[ERROR] $operationName failed with exit code: $($p.ExitCode)" -ForegroundColor Red
            return @{ Ok = $false; StdOut = $out; StdErr = $err; Code = $p.ExitCode }
        } else {
            if ($statusLabel) { $statusLabel.Text = "$operationName completed" }
            Write-Host "[OK] $operationName completed" -ForegroundColor Green
            return @{ Ok = $true; StdOut = $out; StdErr = $err; Code = 0 }
        }
    } catch {
        Write-Host "[CRASH] $($_.Exception.Message)" -ForegroundColor Red
        if ($terminalBox) {
            $terminalBox.AppendText(">> [ERROR] $($_.Exception.Message)`r`n")
        }
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
    PasswordHash = ''
    ParentPath = ''
    WorkspacePath = ''
}

# .env file path - defined early for use throughout the script
$script:envPath = Join-Path $PSScriptRoot '.env'

# Function to hash password using SHA-512 (compatible with Linux chpasswd -e)
function Get-LinuxPasswordHash {
    param([string]$Password)

    # Generate a random 16-character salt for SHA-512
    $saltChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789./'
    $salt = -join ((1..16) | ForEach-Object { $saltChars[(Get-Random -Maximum $saltChars.Length)] })

    # Use Python to generate the hash (available on most systems, and we need Linux-compatible format)
    # Format: $6$salt$hash (SHA-512)
    $pythonCmd = "import sys, crypt; pw = sys.stdin.read().strip(); print(crypt.crypt(pw, '\`$6\`$$salt\`$'))"

    # Since Python may not be available on Windows, use OpenSSL via Docker if available
    # Or fall back to storing password with a marker for the entrypoint to hash it
    try {
        # Try using docker to generate the hash (container has the right tools)
        $hashResult = echo $Password | docker run --rm -i ubuntu:24.04 python3 -c "$pythonCmd" 2>$null
        if ($LASTEXITCODE -eq 0 -and $hashResult) {
            return $hashResult.Trim()
        }
    } catch {
        # Docker not available or failed
    }

    # Fallback: Return empty string, entrypoint will hash it
    return ''
}

Write-Host "[INIT] Checking for existing .env file..." -ForegroundColor Yellow
# Load existing .env file if present (for retry scenarios)
if (Test-Path $script:envPath) {
    Write-Host "[INFO] Found existing .env file - loading saved values" -ForegroundColor Cyan
    $envLines = Get-Content $script:envPath
    foreach ($line in $envLines) {
        if ($line -match '^USER_NAME=(.*)$') { $state.UserName = $Matches[1] }
        # Note: We store hashed password in USER_PASSWORD_HASH, plain password is not persisted
        if ($line -match '^USER_PASSWORD_HASH=(.*)$') { $state.PasswordHash = $Matches[1] }
        if ($line -match '^WORKSPACE_PATH=(.*)$') {
            $state.WorkspacePath = $Matches[1]
            $state.ParentPath = Split-Path $Matches[1] -Parent
        }
    }
    if ($state.UserName) {
        Write-Host "[INFO] Loaded credentials for user: $($state.UserName)" -ForegroundColor Green
        if ($state.PasswordHash) {
            Write-Host "[INFO] Password hash found (password is securely stored)" -ForegroundColor Green
        }
    }
}

Write-Host "[INIT] Detecting Docker files location..." -ForegroundColor Yellow
# Docker files location - detect if running from embedded exe or project directory
# If running from AppData\AI-Docker-CLI\docker-files (embedded exe), use current directory
# If running from project scripts folder, use ../docker
$dockerPath = if ($PSScriptRoot -like '*AI-Docker-CLI*docker-files*') {
    # Running from embedded exe - docker files are in same folder
    $PSScriptRoot
} else {
    # Running from project directory - docker files are in ../docker
    Join-Path $PSScriptRoot '..\docker'
}

$composePath = Join-Path $dockerPath 'docker-compose.yml'
Write-Host "[INIT] Docker path: $dockerPath" -ForegroundColor Cyan
Write-Host "[INIT] Compose path: $composePath" -ForegroundColor Cyan
if ((-not $script:IsDevMode) -and (-not (Test-Path $composePath))) {
    Write-Host "[ERROR] docker-compose.yml not found!" -ForegroundColor Red
    Show-Error ('docker-compose.yml not found at: ' + $composePath + [Environment]::NewLine + [Environment]::NewLine + 'Project structure may be incorrect.' + [Environment]::NewLine + [Environment]::NewLine + 'Script location: ' + $PSScriptRoot + [Environment]::NewLine + 'Looking for: ' + $composePath)
    exit 1  # Exit with error code
}
Write-Host "[INIT] Docker compose file found" -ForegroundColor Green

# ---------- main form ----------
Write-Host "[INIT] Creating main form window..." -ForegroundColor Yellow
$form = New-Object System.Windows.Forms.Form
if ($script:IsDevMode) {
    $form.Text = '>>> AI CLI DOCKER SETUP :: [DEV MODE] <<<'
} else {
    $form.Text = '>>> AI CLI DOCKER SETUP :: MATRIX PROTOCOL <<<'
}
$form.Width = 950
$form.Height = 700
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:MatrixDarkGreen
$form.ForeColor = $script:MatrixGreen
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.TopMost = $true  # Ensure form comes to front when launched

# Bring form to front when shown, then disable TopMost so user can interact with other windows
$form.Add_Shown({
    $this.Activate()
    $this.BringToFront()
    $this.TopMost = $false
})

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
$p0.Controls.Add((New-Label '>> Auto-install AI CLI tools (Claude, GitHub CLI, Gemini, OpenAI SDK, Codex)' 20 280 880 24 10 $false $true))
$p0.Controls.Add((New-Label '' 20 305 880 24 10 $false $true))
$p0.Controls.Add((New-Label '[!] NOTE: Do not move the AI_Work folder after setup - it will break the configuration' 20 330 880 24 10 $false $true))
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
$p1.Controls.Add((New-LinkLabel 'https://www.docker.com/resources/what-container/' 20 180 880 24 9))
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
$p1.Controls.Add((New-Label 'Note: Password will be hashed (SHA-512) before storing in the .env file.' 20 425 880 24 9 $false $true))
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

# Pre-populate textboxes from loaded .env values (for retry scenarios)
if ($state.UserName) { $script:tbUser.Text = $state.UserName }
if ($state.Password) {
    $script:tbPass.Text = $state.Password
    $script:tbPassConfirm.Text = $state.Password
}
if ($state.ParentPath) { $script:tbParent.Text = $state.ParentPath }

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
$p3.Controls.Add((New-LinkLabel 'https://docs.docker.com/desktop/setup/install/windows-install/' 20 345 880 24 9))
$p3.Controls.Add((New-Label '' 20 370 880 24 10 $false $true))
$p3.Controls.Add((New-Label '>> After installing, ensure Docker Desktop is running (check system tray)' 20 395 880 24 9 $false $true))
$p3.Controls.Add((New-Label '' 20 420 880 24 10 $false $true))
$p3.Controls.Add((New-Label '>> Then click "Retry Check" to verify it''s running' 20 445 880 24 9 $false $true))
$pages += $p3

$btnRetryDock.Add_Click({
    $script:lblDock.Text = 'Checking Docker status...'
    [System.Windows.Forms.Application]::DoEvents()
    if (Docker-Running) {
        $script:lblDock.Text = '[OK] ' + $script:Arrow + ' Docker is running! Click "Next" to continue.'
        $script:lblDock.ForeColor = $script:MatrixGreen
    } else {
        $script:lblDock.Text = '[ERROR] ' + $script:Arrow + ' Docker is not running. Please start Docker Desktop and retry.'
        $script:lblDock.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
    }
})

# Page 4: Build/Up
$p4 = New-PanelPage
$p4.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p4.Controls.Add((New-Label -text 'BUILDING AND DEPLOYING CONTAINER' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p4.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))

# Dynamic status label for current operation
$script:lblBuildStatus = New-Label 'Preparing to build...' 20 75 880 24 10 $true $true
$p4.Controls.Add($script:lblBuildStatus)

# Force rebuild checkbox (unchecked = use cache if image exists)
$script:chkForceRebuild = New-Object System.Windows.Forms.CheckBox
$script:chkForceRebuild.Text = "Force rebuild (ignore cached image)"
$script:chkForceRebuild.Left = 20
$script:chkForceRebuild.Top = 100
$script:chkForceRebuild.Width = 300
$script:chkForceRebuild.Height = 24
$script:chkForceRebuild.ForeColor = $script:MatrixGreen
$script:chkForceRebuild.BackColor = [System.Drawing.Color]::Transparent
$script:chkForceRebuild.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:chkForceRebuild.Checked = $false
$p4.Controls.Add($script:chkForceRebuild)

# Terminal display for build output (like Page 5)
$script:buildTerminalBox = New-Object System.Windows.Forms.RichTextBox
$script:buildTerminalBox.Left = 20
$script:buildTerminalBox.Top = 130
$script:buildTerminalBox.Width = 880
$script:buildTerminalBox.Height = 350
$script:buildTerminalBox.BackColor = [System.Drawing.Color]::Black
$script:buildTerminalBox.ForeColor = $script:MatrixGreen
$script:buildTerminalBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:buildTerminalBox.ReadOnly = $true
$script:buildTerminalBox.ScrollBars = 'Vertical'
$script:buildTerminalBox.BorderStyle = 'FixedSingle'
$script:buildTerminalBox.Text = ">> Waiting for build to begin...`r`n"
$p4.Controls.Add($script:buildTerminalBox)

$pages += $p4

# Page 5: Install CLI Tools
$p5 = New-PanelPage
$p5.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p5.Controls.Add((New-Label -text 'INSTALLING AI CLI TOOLS' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p5.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
# Dynamic label for current tool being installed
$script:lblCurrentTool = New-Label 'Initializing installation...' 20 75 880 24 10 $true $true
$p5.Controls.Add($script:lblCurrentTool)
$p5.Controls.Add((New-Label 'Tools: GitHub CLI, Claude Code, Gemini, OpenAI SDK, Codex' 20 100 880 20 9 $false $true))

# Mini terminal display for installation output
$script:terminalBox = New-Object System.Windows.Forms.RichTextBox
$script:terminalBox.Left = 20
$script:terminalBox.Top = 130
$script:terminalBox.Width = 880
$script:terminalBox.Height = 350
$script:terminalBox.BackColor = [System.Drawing.Color]::Black
$script:terminalBox.ForeColor = $script:MatrixGreen
$script:terminalBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:terminalBox.ReadOnly = $true
$script:terminalBox.ScrollBars = 'Vertical'
$script:terminalBox.BorderStyle = 'FixedSingle'
$script:terminalBox.Text = ">> Waiting for installation to begin...`r`n"
$p5.Controls.Add($script:terminalBox)

$pages += $p5

# Page 6: Codex Subscription Auth (Optional)
$p6 = New-PanelPage
$p6.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p6.Controls.Add((New-Label -text 'CODEX SUBSCRIPTION AUTHENTICATION (OPTIONAL)' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p6.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p6.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p6.Controls.Add((New-Label 'Codex CLI can use your ChatGPT Plus/Pro subscription (no API credits needed).' 20 95 880 24 10 $false $true))
$p6.Controls.Add((New-Label '' 20 115 880 24 10 $false $true))
$p6.Controls.Add((New-Label 'This step will:' 20 135 880 24 10 $true $true))
$p6.Controls.Add((New-Label '  1. Temporarily install Codex on Windows' 20 155 880 24 9 $false $true))
$p6.Controls.Add((New-Label '  2. Open your browser to sign in with your OpenAI account' 20 175 880 24 9 $false $true))
$p6.Controls.Add((New-Label '  3. Copy your authentication to the Docker container' 20 195 880 24 9 $false $true))
$p6.Controls.Add((New-Label '  4. Ask if you want to keep or remove Codex from Windows' 20 215 880 24 9 $false $true))
$p6.Controls.Add((New-Label '' 20 240 880 24 10 $false $true))

# Status label for Codex setup
$script:lblCodexStatus = New-Label 'Click "Setup Codex Auth" to begin, or "Skip" to continue without Codex.' 20 265 880 30 10 $true $true
$p6.Controls.Add($script:lblCodexStatus)

# Terminal box for Codex setup output (reduced height to fit buttons above progress bar)
$script:codexTerminalBox = New-Object System.Windows.Forms.RichTextBox
$script:codexTerminalBox.Left = 20
$script:codexTerminalBox.Top = 300
$script:codexTerminalBox.Width = 880
$script:codexTerminalBox.Height = 150
$script:codexTerminalBox.BackColor = [System.Drawing.Color]::Black
$script:codexTerminalBox.ForeColor = $script:MatrixGreen
$script:codexTerminalBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:codexTerminalBox.ReadOnly = $true
$script:codexTerminalBox.ScrollBars = 'Vertical'
$script:codexTerminalBox.BorderStyle = 'FixedSingle'
$script:codexTerminalBox.Text = ">> Waiting for user action...`r`n"
$p6.Controls.Add($script:codexTerminalBox)

# Setup Codex button (positioned below terminal, above progress bar)
$btnSetupCodex = New-Button 'Setup Codex Auth' 300 460 180 35
$btnSetupCodex.BackColor = [System.Drawing.Color]::FromArgb(0, 60, 20)
$p6.Controls.Add($btnSetupCodex)

# Skip button
$btnSkipCodex = New-Button 'Skip' 500 460 100 35
$p6.Controls.Add($btnSkipCodex)

# Track if Codex setup was completed or skipped
$script:codexSetupDone = $false

$btnSkipCodex.Add_Click({
    $script:codexSetupDone = $true
    $script:lblCodexStatus.Text = 'Codex setup skipped. You can configure it later with: configure-tools --codex'
    $script:codexTerminalBox.AppendText(">> Skipped Codex authentication setup`r`n")
    Write-Host "[INFO] User skipped Codex authentication" -ForegroundColor Yellow
    # Auto-advance to next page
    $script:current++
    Show-Page $script:current
})

$btnSetupCodex.Add_Click({
    $script:codexTerminalBox.Text = ">> Starting Codex authentication setup...`r`n"
    $script:lblCodexStatus.Text = 'Validating Node.js/npm installation...'
    $script:lblCodexStatus.ForeColor = $script:MatrixGreen  # Reset color
    [System.Windows.Forms.Application]::DoEvents()

    # Validate npm is working correctly (not just that it exists)
    $script:codexTerminalBox.AppendText(">> Validating npm installation...`r`n")
    [System.Windows.Forms.Application]::DoEvents()
    $npmCheck = Test-NpmFunctional

    if (-not $npmCheck.Valid) {
        $errorMessage = $npmCheck.Error

        # Check if npm needs repair vs fresh install
        if ($npmCheck.NeedsRepair) {
            $script:codexTerminalBox.AppendText("[WARNING] npm exists but is not functioning correctly`r`n")
            $script:codexTerminalBox.AppendText("[WARNING] Error: $errorMessage`r`n")
            $script:codexTerminalBox.AppendText("`r`n>> Attempting to repair npm...`r`n")
            [System.Windows.Forms.Application]::DoEvents()

            $repairResult = Repair-NpmInstallation
            if ($repairResult.Valid) {
                $script:codexTerminalBox.AppendText("[OK] npm repair successful!`r`n")
                $npmCheck = $repairResult
            } else {
                $script:codexTerminalBox.AppendText("[ERROR] npm repair failed`r`n")
                $script:codexTerminalBox.AppendText("[INFO] Please reinstall Node.js from nodejs.org`r`n")
                $script:lblCodexStatus.Text = 'npm repair failed. Please reinstall Node.js.'
                $script:lblCodexStatus.ForeColor = [System.Drawing.Color]::Red

                if (-not $script:IsDevMode) {
                    Start-Process "https://nodejs.org/"
                }
                return
            }
        } else {
            # npm not installed at all
            $script:codexTerminalBox.AppendText("[ERROR] Node.js/npm is not installed on Windows`r`n")
            Write-Host "[ERROR] npm not found - Node.js not installed" -ForegroundColor Red

            # Offer to auto-install Node.js (skip in DEV MODE)
            if (-not $script:IsDevMode) {
                $installResult = [System.Windows.Forms.MessageBox]::Show(
                    "Node.js is required but not installed.`n`n" +
                    "Would you like to install Node.js automatically using winget?`n`n" +
                    "Click 'Yes' to install automatically`n" +
                    "Click 'No' to install manually from nodejs.org",
                    "Install Node.js?",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
            } else {
                Write-Host "[DEV MODE] Skipping Node.js install popup - assuming Yes" -ForegroundColor Magenta
                $installResult = [System.Windows.Forms.DialogResult]::Yes
            }

            if ($installResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                $script:codexTerminalBox.AppendText("`r`n>> Installing Node.js via winget...`r`n")
                $script:lblCodexStatus.Text = 'Installing Node.js (this may take a minute)...'
                [System.Windows.Forms.Application]::DoEvents()

                try {
                    # Try winget first
                    $wingetCheck = Get-Command winget -ErrorAction SilentlyContinue
                    if ($wingetCheck) {
                        $script:codexTerminalBox.AppendText(">> Running: winget install OpenJS.NodeJS.LTS`r`n")
                        [System.Windows.Forms.Application]::DoEvents()

                        $installProc = Start-Process -FilePath "winget" -ArgumentList "install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements" -Wait -PassThru -WindowStyle Normal

                        if ($installProc.ExitCode -eq 0) {
                            $script:codexTerminalBox.AppendText("[OK] Node.js installed successfully!`r`n")
                            $script:codexTerminalBox.AppendText("`r`n>> Please click 'Setup Codex Auth' again to continue.`r`n")
                            $script:lblCodexStatus.Text = 'Node.js installed! Click "Setup Codex Auth" again to continue.'
                            $script:lblCodexStatus.ForeColor = $script:MatrixGreen

                            # Refresh PATH for this session
                            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                        } else {
                            $script:codexTerminalBox.AppendText("[WARNING] winget install may have failed. Try clicking Setup again.`r`n")
                            $script:lblCodexStatus.Text = 'Installation may have completed. Click "Setup Codex Auth" to retry.'
                        }
                    } else {
                        $script:codexTerminalBox.AppendText("[ERROR] winget not available`r`n")
                        $script:codexTerminalBox.AppendText(">> Opening Node.js download page...`r`n")
                        Start-Process "https://nodejs.org/"
                        $script:lblCodexStatus.Text = 'Install Node.js from the browser, then click "Setup Codex Auth" again.'
                    }
                } catch {
                    $script:codexTerminalBox.AppendText("[ERROR] Auto-install failed: $($_.Exception.Message)`r`n")
                    $script:lblCodexStatus.Text = 'Auto-install failed. Click "Setup Codex Auth" to retry after manual install.'
                }
            } else {
                # User chose manual install - open browser
                $script:codexTerminalBox.AppendText("`r`n>> Opening Node.js download page...`r`n")
                Start-Process "https://nodejs.org/"
                $script:codexTerminalBox.AppendText(">> After installing, click 'Setup Codex Auth' again.`r`n")
                $script:lblCodexStatus.Text = 'Install Node.js from the browser, then click "Setup Codex Auth" again.'
            }
            return
        }
    }

    $script:codexTerminalBox.AppendText("[OK] Node.js/npm validated (version: $($npmCheck.Version))`r`n")
    Write-Host "[OK] npm validated at: $($npmCheck.Path)" -ForegroundColor Green

    # Install Codex globally
    $script:lblCodexStatus.Text = 'Installing Codex CLI on Windows (temporary)...'
    $script:codexTerminalBox.AppendText("`r`n>> Installing @openai/codex globally...`r`n")
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $installResult = & npm install -g @openai/codex 2>&1
        $script:codexTerminalBox.AppendText("$installResult`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    } catch {
        $script:codexTerminalBox.AppendText("[ERROR] Failed to install Codex: $($_.Exception.Message)`r`n")
        $script:lblCodexStatus.Text = 'Failed to install Codex. Check console for details.'
        return
    }

    # Find codex executable
    $codexPath = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $codexPath) {
        # Try common npm global paths
        $npmPrefix = & npm config get prefix 2>$null
        $possibleCodex = Join-Path $npmPrefix "codex.cmd"
        if (Test-Path $possibleCodex) {
            $codexPath = @{ Source = $possibleCodex }
        } else {
            $script:codexTerminalBox.AppendText("[ERROR] Codex installed but not found in PATH`r`n")
            $script:lblCodexStatus.Text = 'Codex not found. Try restarting setup.'
            return
        }
    }

    $script:codexTerminalBox.AppendText("[OK] Codex CLI installed`r`n")

    # Show instructions before launching auth (skip in DEV MODE for faster testing)
    if (-not $script:IsDevMode) {
        $authInstructions = [System.Windows.Forms.MessageBox]::Show(
            "Codex is now ready for authentication.`n`n" +
            "What will happen next:`n" +
            "1. A command window will open running 'codex auth login'`n" +
            "2. Your browser will open to the OpenAI login page`n" +
            "3. Sign in with your OpenAI account (ChatGPT Plus/Pro)`n" +
            "4. After signing in, return to this wizard`n`n" +
            "The OAuth server will run on your Windows machine,`n" +
            "so the localhost callback will work correctly.`n`n" +
            "Click OK to begin authentication.",
            "Codex Authentication Instructions",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } else {
        Write-Host "[DEV MODE] Skipping Codex auth instructions popup" -ForegroundColor Magenta
    }

    # Launch Codex for authentication
    $script:lblCodexStatus.Text = 'Opening browser for authentication... Please sign in.'
    $script:codexTerminalBox.AppendText("`r`n>> Launching Codex authentication...`r`n")
    $script:codexTerminalBox.AppendText(">> Your browser will open - please sign in with your OpenAI account`r`n")
    $script:codexTerminalBox.AppendText(">> A local server will start on Windows to handle the OAuth callback`r`n")
    $script:codexTerminalBox.AppendText(">> Waiting for authentication to complete...`r`n")
    $script:codexTerminalBox.AppendText("`r`n>> Running: codex auth login`r`n")
    [System.Windows.Forms.Application]::DoEvents()

    # Run 'codex auth login' properly through cmd.exe in a new window
    # This will:
    # 1. Start a local OAuth server on Windows (listening on localhost:1455)
    # 2. Open browser to OpenAI OAuth page
    # 3. Handle the redirect to localhost:1455/auth/callback
    # 4. Save the token to %USERPROFILE%\.codex\auth.json
    $codexAuthProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/k", "codex", "auth", "login" -PassThru -WindowStyle Normal

    $script:codexTerminalBox.AppendText("[INFO] Codex auth window opened - follow instructions in the new window`r`n")
    $script:codexTerminalBox.AppendText("[INFO] After signing in, the browser will redirect to localhost:1455`r`n")
    $script:codexTerminalBox.AppendText("[INFO] The auth window will show success message when complete`r`n")
    $script:codexTerminalBox.AppendText("[INFO] You can close the cmd window after seeing 'Authentication successful'`r`n")

    # Wait for auth.json to appear (poll every 3 seconds, max 5 minutes for user to complete auth)
    $authFile = Join-Path $env:USERPROFILE ".codex\auth.json"
    $maxWait = 300
    $waited = 0

    while ($waited -lt $maxWait) {
        if (Test-Path $authFile) {
            $script:codexTerminalBox.AppendText("`r`n[SUCCESS] Authentication completed!`r`n")
            $script:codexTerminalBox.AppendText("[SUCCESS] Found auth.json at: $authFile`r`n")
            Write-Host "[SUCCESS] Codex auth.json found" -ForegroundColor Green

            # Auto-close the Codex auth cmd window now that auth is complete
            if ($codexAuthProcess -and -not $codexAuthProcess.HasExited) {
                $script:codexTerminalBox.AppendText("[INFO] Closing Codex auth window automatically...`r`n")
                Write-Host "[INFO] Auto-closing Codex auth window" -ForegroundColor Cyan
                try {
                    $codexAuthProcess.CloseMainWindow() | Out-Null
                    Start-Sleep -Milliseconds 500
                    if (-not $codexAuthProcess.HasExited) {
                        $codexAuthProcess.Kill()
                    }
                    $script:codexTerminalBox.AppendText("[OK] Auth window closed`r`n")
                } catch {
                    Write-Host "[WARNING] Could not auto-close auth window: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            break
        }
        # Use smaller sleep increments to keep UI responsive (prevents "Not Responding")
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 100
            [System.Windows.Forms.Application]::DoEvents()
        }
        $waited += 3
        $remainingTime = $maxWait - $waited
        $script:lblCodexStatus.Text = "Waiting for authentication... ($waited/$maxWait seconds - $remainingTime remaining)"
        [System.Windows.Forms.Application]::DoEvents()
    }

    if (-not (Test-Path $authFile)) {
        $script:codexTerminalBox.AppendText("`r`n[TIMEOUT] Authentication not completed within 5 minutes`r`n")
        $script:codexTerminalBox.AppendText("[INFO] You can try again by clicking 'Setup Codex Auth' or click 'Skip'`r`n")
        $script:lblCodexStatus.Text = 'Authentication timed out. Try again or click Skip to continue.'
        return
    }

    # Copy auth to container
    $script:lblCodexStatus.Text = 'Copying authentication to container...'
    $script:codexTerminalBox.AppendText("`r`n>> Copying auth to Docker container...`r`n")
    [System.Windows.Forms.Application]::DoEvents()

    # Get username - try from state first, then from .env file
    $containerUser = $state.UserName
    if (-not $containerUser) {
        # Try to read from .env file
        $envFile = Join-Path $PSScriptRoot ".env"
        if (Test-Path $envFile) {
            $envContent = Get-Content $envFile
            foreach ($line in $envContent) {
                if ($line -match '^USER_NAME=(.+)$') {
                    $containerUser = $matches[1]
                    break
                }
            }
        }
    }

    if (-not $containerUser) {
        $containerUser = "user"  # Fallback default
        $script:codexTerminalBox.AppendText("[WARNING] Could not determine container username, using 'user'`r`n")
    }

    $script:codexTerminalBox.AppendText(">> Target user: $containerUser`r`n")
    $script:codexTerminalBox.AppendText(">> Source file: $authFile`r`n")
    Write-Host "[DEBUG] Copying auth for user: $containerUser" -ForegroundColor Cyan

    try {
        # Ensure .codex directory exists
        $script:codexTerminalBox.AppendText(">> Creating .codex directory...`r`n")
        $mkdirResult = & docker exec ai-cli mkdir -p "/home/$containerUser/.codex" 2>&1
        if ($LASTEXITCODE -ne 0) {
            $script:codexTerminalBox.AppendText("[ERROR] mkdir failed: $mkdirResult`r`n")
        }

        & docker exec ai-cli chown "${containerUser}:${containerUser}" "/home/$containerUser/.codex" 2>&1 | Out-Null

        # Copy auth file
        $script:codexTerminalBox.AppendText(">> Copying auth.json...`r`n")
        $copyResult = & docker cp $authFile "ai-cli:/home/$containerUser/.codex/auth.json" 2>&1
        if ($LASTEXITCODE -ne 0) {
            $script:codexTerminalBox.AppendText("[ERROR] docker cp failed: $copyResult`r`n")
            throw "Docker cp failed"
        }

        & docker exec ai-cli chown "${containerUser}:${containerUser}" "/home/$containerUser/.codex/auth.json" 2>&1 | Out-Null
        & docker exec ai-cli chmod 600 "/home/$containerUser/.codex/auth.json" 2>&1 | Out-Null

        # Verify the file was copied
        $verifyResult = & docker exec ai-cli test -f "/home/$containerUser/.codex/auth.json" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:codexTerminalBox.AppendText("[OK] Auth copied and verified in container`r`n")
            Write-Host "[SUCCESS] Auth copied to container" -ForegroundColor Green
        } else {
            $script:codexTerminalBox.AppendText("[ERROR] Auth file not found in container after copy!`r`n")
            throw "Verification failed"
        }
    } catch {
        $script:codexTerminalBox.AppendText("[ERROR] Could not copy auth: $($_.Exception.Message)`r`n")
        Write-Host "[ERROR] Auth copy failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Ask user about cleanup (skip popup in DEV MODE but still auto-remove for security)
    if (-not $script:IsDevMode) {
        $cleanupResult = [System.Windows.Forms.MessageBox]::Show(
            "Codex authentication was successful!`n`nWould you like to REMOVE Codex from Windows?`n`n" +
            "This will:`n" +
            "- Uninstall @openai/codex from npm`n" +
            "- Delete the .codex folder (your auth is already copied to Docker)`n`n" +
            "WARNING: If you use Codex outside of this Docker setup, click 'No'.`n`n" +
            "- Click 'Yes' to remove (recommended if only using Docker)`n" +
            "- Click 'No' to keep Codex installed on Windows",
            "Remove Codex from Windows?",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    } else {
        Write-Host "[DEV MODE] Skipping Codex cleanup popup - auto-removing for security" -ForegroundColor Magenta
        $cleanupResult = [System.Windows.Forms.DialogResult]::Yes  # Auto-remove in DEV MODE
    }

    if ($cleanupResult -eq [System.Windows.Forms.DialogResult]::Yes) {
        $script:lblCodexStatus.Text = 'Removing Codex from Windows...'
        $script:codexTerminalBox.AppendText("`r`n>> Uninstalling Codex from Windows...`r`n")
        [System.Windows.Forms.Application]::DoEvents()

        try {
            # Uninstall Codex from npm
            $script:codexTerminalBox.AppendText(">> Running: npm uninstall -g @openai/codex`r`n")
            $uninstallResult = & npm uninstall -g @openai/codex 2>&1
            $script:codexTerminalBox.AppendText("$uninstallResult`r`n")

            # Remove .codex folder from Windows (contains auth.json we already copied)
            $codexFolder = Join-Path $env:USERPROFILE ".codex"
            if (Test-Path $codexFolder) {
                # Check for running Codex processes before deletion
                $codexProcesses = Get-Process -Name "*codex*" -ErrorAction SilentlyContinue
                if ($codexProcesses) {
                    $script:codexTerminalBox.AppendText("[WARNING] Codex processes are running - skipping .codex folder removal`r`n")
                    $script:codexTerminalBox.AppendText("[INFO] Close Codex and manually delete: $codexFolder`r`n")
                    Write-Host "[WARNING] Codex processes running, skipping folder removal" -ForegroundColor Yellow
                } else {
                    $script:codexTerminalBox.AppendText(">> Removing .codex folder from Windows...`r`n")
                    Remove-Item -Path $codexFolder -Recurse -Force -ErrorAction SilentlyContinue
                    $script:codexTerminalBox.AppendText("[OK] Removed .codex folder from Windows`r`n")
                }
            }

            # Verify removal
            $codexCheck = Get-Command codex -ErrorAction SilentlyContinue
            if ($codexCheck) {
                $script:codexTerminalBox.AppendText("[WARNING] Codex command still found in PATH`r`n")
                $script:codexTerminalBox.AppendText("[INFO] You may need to restart your terminal or system`r`n")
                Write-Host "[WARNING] Codex may still be cached in PATH" -ForegroundColor Yellow
            } else {
                $script:codexTerminalBox.AppendText("[VERIFIED] Codex successfully removed from Windows`r`n")
                Write-Host "[SUCCESS] Codex verified removed from Windows" -ForegroundColor Green
            }

            $script:codexTerminalBox.AppendText("[OK] Codex cleanup complete`r`n")
        } catch {
            $script:codexTerminalBox.AppendText("[WARNING] Could not fully uninstall: $($_.Exception.Message)`r`n")
        }
    } else {
        $script:codexTerminalBox.AppendText("`r`n>> Keeping Codex installed on Windows`r`n")
        Write-Host "[INFO] User chose to keep Codex on Windows" -ForegroundColor Yellow
    }

    $script:codexSetupDone = $true
    $script:lblCodexStatus.Text = 'Codex authentication complete! Advancing to finish...'
    $script:lblCodexStatus.ForeColor = $script:MatrixGreen
    $script:codexTerminalBox.AppendText("`r`n>> CODEX SETUP COMPLETE!`r`n")
    $script:codexTerminalBox.AppendText(">> You can now use 'codex' in your Docker container with your subscription.`r`n")
    Write-Host "[SUCCESS] Codex setup complete" -ForegroundColor Green

    # Auto-advance to the Done page after successful setup
    Start-Sleep -Milliseconds 1500  # Brief pause so user can see success message
    $script:current++
    Show-Page $script:current
})

$pages += $p6

# Page 7: Done
$p7 = New-PanelPage
$p7.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 10 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p7.Controls.Add((New-Label -text 'SETUP COMPLETE - YOUR AI ENVIRONMENT IS READY!' -x 20 -y 30 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p7.Controls.Add((New-Label -text '==================================================================================' -x 20 -y 50 -w 880 -h 20 -fontSize 10 -bold $true -center $true))
$p7.Controls.Add((New-Label '' 20 75 880 24 10 $false $true))
$p7.Controls.Add((New-Label 'AI CLI Tools Environment successfully initialized!' 20 95 880 24 10 $true $true))
$p7.Controls.Add((New-Label '' 20 120 880 24 10 $false $true))
$p7.Controls.Add((New-Label 'INSTALLED TOOLS: Claude Code, GitHub CLI, Gemini CLI, OpenAI SDK, Codex CLI' 20 140 880 24 10 $true $true))
$p7.Controls.Add((New-Label '' 20 165 880 24 10 $false $true))
$p7.Controls.Add((New-Label 'GETTING STARTED - Quick Setup:' 20 190 880 24 10 $true $true))
$p7.Controls.Add((New-Label '' 20 210 880 24 10 $false $true))
$p7.Controls.Add((New-Label '1. Click "LAUNCH AI WORKSPACE" on the main menu' 20 235 880 24 9 $false $true))
$p7.Controls.Add((New-Label '' 20 255 880 24 10 $false $true))
$p7.Controls.Add((New-Label '2. In the terminal, run: configure-tools' 20 280 880 24 9 $false $true))
$p7.Controls.Add((New-Label '   - This wizard will help you sign into all AI services' 20 300 880 24 9 $false $true))
$p7.Controls.Add((New-Label '   - You can skip tools you don''t have API keys for' 20 320 880 24 9 $false $true))
$p7.Controls.Add((New-Label '' 20 340 880 24 10 $false $true))
$p7.Controls.Add((New-Label 'AVAILABLE COMMANDS:' 20 365 880 24 10 $true $true))
$p7.Controls.Add((New-Label '   claude, gh, gemini, codex' 20 385 880 24 9 $false $true))
$p7.Controls.Add((New-Label '' 20 405 880 24 10 $false $true))
$p7.Controls.Add((New-Label 'MANAGEMENT COMMANDS:' 20 430 880 24 10 $true $true))
$p7.Controls.Add((New-Label '   update-tools (check for updates), config-status (view config)' 20 450 880 24 9 $false $true))
$pages += $p7

# ---------- page plumbing ----------
$form.Controls.Add($pages[0])
$script:current = 0
$btnBack.Enabled = $false
function Show-Page([int]$i) {
    foreach ($p in $pages) { if ($form.Controls.Contains($p)) { $form.Controls.Remove($p) } }
    $form.Controls.Add($pages[$i])
    $btnBack.Enabled = ($i -gt 0)
    if ($i -eq $pages.Count-1) { $btnNext.Text = 'Finish' } else { $btnNext.Text = 'Next' }

    # Hide progress bar on Codex auth page (page 6) to avoid overlap with Setup/Skip buttons
    if ($i -eq 6) {
        $progress.Visible = $false
        $status.Visible = $false
    } else {
        $progress.Visible = $true
        $status.Visible = $true
    }
}
$btnCancel.Add_Click({
    Write-Host '[WARNING] User requested cancellation' -ForegroundColor Yellow

    # Confirm cancellation if on a critical page (skip in DEV MODE for easy testing)
    if (($script:current -eq 4 -or $script:current -eq 5) -and -not $script:IsDevMode) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Setup is currently in progress.`n`nAre you sure you want to cancel?`n`nThis may leave the system in an incomplete state.",
            "Cancel Setup?",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-Host '[INFO] User chose to continue setup' -ForegroundColor Cyan
            return
        }
    } elseif ($script:IsDevMode -and ($script:current -eq 4 -or $script:current -eq 5)) {
        Write-Host "[DEV MODE] Skipping cancel confirmation - allowing immediate exit" -ForegroundColor Magenta
    }

    Write-Host '[WARNING] Cancelling setup - cleaning up...' -ForegroundColor Yellow

    # Kill any running process
    if ($script:runningProcess -and -not $script:runningProcess.HasExited) {
        Write-Host '[INFO] Terminating running process...' -ForegroundColor Cyan
        try {
            $script:runningProcess.Kill()
            $script:runningProcess.WaitForExit(5000)
            Write-Host '[INFO] Process terminated' -ForegroundColor Green
        } catch {
            Write-Host '[WARNING] Could not kill process: $($_.Exception.Message)' -ForegroundColor Yellow
        }
    }

    Write-Host '[INFO] Setup cancelled by user' -ForegroundColor Yellow
    $form.Close()
    exit 2  # Exit code 2 = user cancelled (not an error)
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

            if ($script:IsDevMode) {
                Write-Host "[DEV MODE] Skipping credentials validation" -ForegroundColor Magenta
                $state.UserName = "devuser"
                $state.Password = "devpass"
            } else {
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

                # Hash the password for secure storage
                Write-Host "[INFO] Hashing password for secure storage..." -ForegroundColor Cyan
                $state.PasswordHash = Get-LinuxPasswordHash -Password $state.Password
                if ($state.PasswordHash) {
                    Write-Host "[SUCCESS] Password hashed with SHA-512" -ForegroundColor Green
                } else {
                    Write-Host "[INFO] Password will be hashed by container on first run" -ForegroundColor Yellow
                }

                # Save credentials to .env immediately (persist for retry scenarios)
                # Password is stored as hash (USER_PASSWORD_HASH) for security
                Write-Host "[INFO] Saving credentials to .env" -ForegroundColor Cyan
                $nl = [Environment]::NewLine
                if ($state.PasswordHash) {
                    # Store hashed password - entrypoint will use chpasswd -e
                    $envContent = "USER_NAME=$($state.UserName)" + $nl + "USER_PASSWORD_HASH=$($state.PasswordHash)" + $nl
                } else {
                    # Fallback: store plain password with marker for entrypoint to hash
                    $envContent = "USER_NAME=$($state.UserName)" + $nl + "USER_PASSWORD_PLAIN=$($state.Password)" + $nl
                }
                if ($state.WorkspacePath) {
                    $envContent += "WORKSPACE_PATH=$($state.WorkspacePath)" + $nl
                }
                $envContent | Out-File $script:envPath -Encoding UTF8
                Write-Host "[SUCCESS] Credentials saved to .env (password is hashed)" -ForegroundColor Green
            }
            $script:current++; Show-Page $script:current
        }
        2 {
            Write-Host "[DEBUG] Page 2: Folder selection" -ForegroundColor Cyan

            if ($script:IsDevMode) {
                Write-Host "[DEV MODE] Skipping folder validation and .env creation" -ForegroundColor Magenta
                $state.ParentPath = "C:\DEV_MODE_PATH"
                $state.WorkspacePath = "C:\DEV_MODE_PATH\AI_Work"
            } else {
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

                # Update .env with workspace path
                Write-Host "[INFO] Updating .env with workspace path" -ForegroundColor Cyan
                $nl = [Environment]::NewLine
                if ($state.PasswordHash) {
                    $envContent = "USER_NAME=$($state.UserName)" + $nl + "USER_PASSWORD_HASH=$($state.PasswordHash)" + $nl + "WORKSPACE_PATH=$($state.WorkspacePath)" + $nl
                } else {
                    $envContent = "USER_NAME=$($state.UserName)" + $nl + "USER_PASSWORD_PLAIN=$($state.Password)" + $nl + "WORKSPACE_PATH=$($state.WorkspacePath)" + $nl
                }
                $envContent | Out-File $script:envPath -Encoding UTF8
                $status.Text = ".env updated at $script:envPath"
                Write-Host "[SUCCESS] .env updated with workspace path" -ForegroundColor Green
            }

            $script:current++; Show-Page $script:current

            if ($script:IsDevMode) {
                Write-Host "[DEV MODE] Simulating Docker check as running" -ForegroundColor Magenta
                $script:lblDock.Text = '[DEV MODE] Docker check simulated as running. Click Next.'
            } else {
                Write-Host "[INFO] Checking Docker status..." -ForegroundColor Cyan
                if (Docker-Running) {
                    Write-Host "[SUCCESS] Docker is running" -ForegroundColor Green
                    $script:lblDock.Text = '[OK] ' + $script:Arrow + ' Docker is running. Click Next to continue.'
                } else {
                    Write-Host "[WARNING] Docker not running" -ForegroundColor Yellow
                    $script:lblDock.Text = '[ERROR] ' + $script:Arrow + ' Docker not running. Start Docker Desktop, then Retry.'
                }
            }
        }
        3 {
            Write-Host "[DEBUG] Page 3: Docker check" -ForegroundColor Cyan

            if ($script:IsDevMode) {
                Write-Host "[DEV MODE] Skipping Docker running check" -ForegroundColor Magenta
            } else {
                if (-not (Docker-Running)) {
                    Write-Host "[ERROR] Docker is not running" -ForegroundColor Red
                    Show-Error 'docker is not running. open Docker Desktop, then click Retry.'
                    return
                }
            }
            Write-Host "[SUCCESS] Docker verified - proceeding to build page" -ForegroundColor Green
            $script:current++; Show-Page $script:current
            # STOP HERE - let user see Page 4 and toggle Force Rebuild checkbox if needed
            # Build will start when user clicks Next on Page 4 (case 4)
        }
        4 {
            # Build/Deploy page - user clicked Next, start the build process
            Write-Host "[DEBUG] Page 4: Starting build process" -ForegroundColor Cyan

            # DEV MODE: Skip all Docker operations
            if ($script:IsDevMode) {
                Write-Host "[DEV MODE] Simulating docker compose build..." -ForegroundColor Magenta
                $status.Text = '[DEV MODE] Simulating build...'
                Start-Sleep -Milliseconds 500
                $progress.Value = 50
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 500
                $progress.Value = 100
                [System.Windows.Forms.Application]::DoEvents()
                Write-Host "[DEV MODE] Build simulation complete" -ForegroundColor Magenta

                Write-Host "[DEV MODE] Simulating docker compose up..." -ForegroundColor Magenta
                $status.Text = '[DEV MODE] Simulating container start...'
                Start-Sleep -Milliseconds 500
                $progress.Value = 0
                [System.Windows.Forms.Application]::DoEvents()

                # Move to install page
                $script:current++; Show-Page $script:current

                Write-Host "[DEV MODE] Simulating CLI tools installation..." -ForegroundColor Magenta
                $status.Text = '[DEV MODE] Simulating CLI tools install...'

                # Simulate terminal output for DEV MODE
                $script:terminalBox.Text = ">> [DEV MODE] Installation simulation starting...`r`n"
                [System.Windows.Forms.Application]::DoEvents()

                $devModeLines = @(
                    "[INFO] Starting CLI tools installation...",
                    "[INFO] Updating package lists...",
                    "[INFO] Installing GitHub CLI...",
                    "[SUCCESS] GitHub CLI installed successfully",
                    "[INFO] Installing/Updating Claude Code CLI...",
                    "[SUCCESS] Claude Code CLI installed/updated successfully",
                    "[INFO] Installing Google Gemini CLI...",
                    "[SUCCESS] Gemini CLI installed successfully",
                    "[INFO] Installing OpenAI CLI tools...",
                    "[SUCCESS] OpenAI Python SDK installed",
                    "[INFO] Installing OpenAI Codex CLI...",
                    "[SUCCESS] OpenAI Codex CLI installed successfully",
                    "[SUCCESS] All CLI tools installation completed!"
                )

                $progressValues = @(10, 15, 20, 30, 40, 50, 55, 65, 75, 85, 90, 95, 100)
                $toolNames = @("", "", "GitHub CLI", "", "Claude Code CLI", "", "Google Gemini CLI", "", "OpenAI Python SDK", "", "OpenAI Codex CLI", "", "")

                for ($i = 0; $i -lt $devModeLines.Count; $i++) {
                    $script:terminalBox.AppendText("$($devModeLines[$i])`r`n")
                    $script:terminalBox.SelectionStart = $script:terminalBox.TextLength
                    $script:terminalBox.ScrollToCaret()
                    $progress.Value = $progressValues[$i]
                    if ($toolNames[$i]) {
                        $script:lblCurrentTool.Text = "Installing $($toolNames[$i])..."
                    }
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 300
                }

                $script:terminalBox.AppendText("`r`n>> INSTALLATION COMPLETE! (simulated)`r`n")
                $script:lblCurrentTool.Text = 'Installation complete!'
                [System.Windows.Forms.Application]::DoEvents()
                Write-Host "[DEV MODE] CLI tools simulation complete" -ForegroundColor Magenta

                # Go to Codex auth page in DEV MODE for testing
                Write-Host "[DEV MODE] Proceeding to Codex auth page for testing" -ForegroundColor Magenta
                $status.Text = '[DEV MODE] Codex auth page (testing)'
                $script:current++  # Go to page 6 (Codex auth)
                Show-Page $script:current
                return
            }

            # Initialize build terminal display
            $script:buildTerminalBox.Text = ">> Build process starting...`r`n"
            $script:buildTerminalBox.SelectionStart = $script:buildTerminalBox.TextLength
            $script:buildTerminalBox.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()

            # Check if image already exists (for caching optimization)
            $forceRebuild = $script:chkForceRebuild.Checked
            $imageExists = $false

            $script:lblBuildStatus.Text = 'Checking for existing Docker image...'
            $script:buildTerminalBox.AppendText(">> Checking for cached image...`r`n")
            [System.Windows.Forms.Application]::DoEvents()

            $imageCheck = Run-Process-UI -file 'docker' -arguments 'images docker-files-ai --format "{{.ID}}"' -progressBar $null -statusLabel $null
            if ($imageCheck.Ok -and $imageCheck.StdOut.Trim()) {
                $imageExists = $true
                $script:buildTerminalBox.AppendText(">> Found existing image: $($imageCheck.StdOut.Trim())`r`n")
                Write-Host "[INFO] Found existing Docker image: $($imageCheck.StdOut.Trim())" -ForegroundColor Green
            } else {
                $script:buildTerminalBox.AppendText(">> No cached image found - will build from scratch`r`n")
                Write-Host "[INFO] No cached image found" -ForegroundColor Yellow
            }

            # Decide whether to build
            $shouldBuild = $true
            if ($imageExists -and -not $forceRebuild) {
                $script:lblBuildStatus.Text = 'Using cached image (skipping build)'
                $script:buildTerminalBox.AppendText("`r`n>> OPTIMIZATION: Using cached image - skipping build step!`r`n")
                $script:buildTerminalBox.AppendText(">> (Check 'Force rebuild' to rebuild from scratch)`r`n`r`n")
                Write-Host "[SUCCESS] Using cached image - skipping docker compose build" -ForegroundColor Green
                $shouldBuild = $false
                Start-Sleep -Milliseconds 500
            }

            if ($shouldBuild) {
                # docker compose build with --progress=plain for readable output
                $script:lblBuildStatus.Text = 'Building Docker image (2-5 minutes first time)...'
                Write-Host "[INFO] Building Docker image - this downloads Ubuntu and installs packages" -ForegroundColor Cyan

                # Use --progress=plain for more readable output in terminal
                # Add --no-cache when force rebuild is checked to ensure fresh build
                if ($forceRebuild) {
                    $buildArgs = 'compose build --no-cache --progress=plain'
                    Write-Host "[INFO] Force rebuild enabled - using --no-cache" -ForegroundColor Yellow
                    $script:buildTerminalBox.AppendText(">> Force rebuild: using --no-cache flag`r`n")
                } else {
                    $buildArgs = 'compose build --progress=plain'
                }
                $r1 = Run-Process-WithTerminal -file 'docker' -arguments $buildArgs -terminalBox $script:buildTerminalBox -statusLabel $script:lblBuildStatus -workingDirectory $dockerPath -operationName 'Docker Build'
                if (-not $r1.Ok) {
                    $errMsg = 'build failed' + [Environment]::NewLine + $r1.StdErr
                    Write-Host "[ERROR] Docker build failed" -ForegroundColor Red
                    Show-Error $errMsg
                    return
                }
                Write-Host "[SUCCESS] Docker image built" -ForegroundColor Green
            }

            # docker compose up -d
            $script:lblBuildStatus.Text = 'Starting container...'
            $script:buildTerminalBox.AppendText("`r`n>> Starting container...`r`n")
            Write-Host "[INFO] Starting container" -ForegroundColor Cyan

            $upArgs = 'compose up -d'
            $r2 = Run-Process-WithTerminal -file 'docker' -arguments $upArgs -terminalBox $script:buildTerminalBox -statusLabel $script:lblBuildStatus -workingDirectory $dockerPath -operationName 'Container Start'
            if (-not $r2.Ok) {
                $errMsg = 'up failed' + [Environment]::NewLine + $r2.StdErr
                Write-Host "[ERROR] Container startup failed" -ForegroundColor Red
                Show-Error $errMsg
                return
            }
            Write-Host "[SUCCESS] Container started" -ForegroundColor Green

            # Wait for container to fully initialize (responsive sleep)
            $script:lblBuildStatus.Text = 'Waiting for container to initialize...'
            $script:buildTerminalBox.AppendText(">> Waiting for container initialization (5 seconds)...`r`n")
            Write-Host "[INFO] Waiting 5 seconds for container to fully initialize..." -ForegroundColor Cyan
            for ($i = 0; $i -lt 50; $i++) {
                Start-Sleep -Milliseconds 100
                [System.Windows.Forms.Application]::DoEvents()
            }

            # Verify container is actually running
            $script:buildTerminalBox.AppendText(">> Verifying container status...`r`n")
            Write-Host "[INFO] Verifying container status..." -ForegroundColor Cyan
            $checkRunning = Run-Process-UI -file 'docker' -arguments 'ps --filter "name=ai-cli" --format "{{.Status}}"' -progressBar $null -statusLabel $null
            if ($checkRunning.Ok -and $checkRunning.StdOut -match 'Up') {
                $script:buildTerminalBox.AppendText(">> Container is running!`r`n")
                Write-Host "[SUCCESS] Container is running" -ForegroundColor Green
            } else {
                $script:buildTerminalBox.AppendText(">> ERROR: Container failed to start!`r`n")
                Write-Host "[ERROR] Container is not running!" -ForegroundColor Red
                Write-Host "[INFO] Checking container logs..." -ForegroundColor Yellow
                $logs = Run-Process-UI -file 'docker' -arguments 'logs ai-cli' -progressBar $null -statusLabel $null
                $script:buildTerminalBox.AppendText(">> Container logs:`r`n$($logs.StdOut)`r`n")
                Write-Host "[LOGS] Container output:" -ForegroundColor Yellow
                Write-Host $logs.StdOut -ForegroundColor Gray
                Show-Error "Container failed to stay running. Check console for logs."
                return
            }
            $script:buildTerminalBox.AppendText("`r`n>> Container ready - proceeding to tool installation...`r`n")
            Write-Host "[SUCCESS] Container ready" -ForegroundColor Green

            $status.Text = 'container started'
            # move to install page
            $script:current++; Show-Page $script:current

            # AI CLI tools will be auto-installed by entrypoint.sh
            $status.Text = 'Installing AI CLI tools suite...'
            Write-Host "[INFO] Container is auto-installing AI CLI tools..." -ForegroundColor Cyan
            Write-Host "[INFO] Installing: Claude, GitHub CLI, Gemini, OpenAI SDK, Codex..." -ForegroundColor Yellow
            Write-Host "[INFO] This will take 3-5 minutes on first run..." -ForegroundColor Yellow
            Write-Host "[INFO] This step requires internet connection" -ForegroundColor Yellow

            # Wait for the entrypoint to run the installation
            $status.Text = 'Waiting for CLI tools installation (3-5 minutes)...'

            # Initialize terminal display
            $script:terminalBox.Text = ">> Installation starting...`r`n"
            $script:terminalBox.SelectionStart = $script:terminalBox.TextLength
            $script:terminalBox.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()

            # Give entry point time to start the installation (responsive sleep)
            for ($i = 0; $i -lt 50; $i++) {
                Start-Sleep -Milliseconds 100
                [System.Windows.Forms.Application]::DoEvents()
            }

            # Track last log position for incremental updates
            $script:lastLogLines = 0

            # Helper function to strip ANSI escape sequences
            # Uses comprehensive pattern to handle all ANSI control sequences including:
            # - Color codes (SGR): \x1b[...m
            # - Cursor movement: \x1b[...H, \x1b[...A/B/C/D, etc.
            # - Screen clearing: \x1b[...J, \x1b[...K
            # - Other control sequences: \x1b[...followed by any letter
            function Strip-AnsiCodes([string]$text) {
                return $text -replace '\x1b\[[0-9;]*[a-zA-Z]', '' -replace '\x1b\][^\x07]*\x07', ''
            }

            # Helper function to update terminal display with new docker logs
            function Update-TerminalDisplay {
                try {
                    # Get recent docker logs (last 100 lines)
                    $logResult = docker logs ai-cli --tail 100 2>&1
                    if ($logResult) {
                        $logLines = $logResult -split "`n"
                        $newLines = $logLines | Select-Object -Skip $script:lastLogLines

                        if ($newLines -and $newLines.Count -gt 0) {
                            foreach ($line in $newLines) {
                                if ($line.Trim()) {
                                    $cleanLine = Strip-AnsiCodes $line
                                    # Add to terminal box
                                    $script:terminalBox.AppendText("$cleanLine`r`n")
                                }
                            }
                            $script:lastLogLines = $logLines.Count
                            # Auto-scroll to bottom
                            $script:terminalBox.SelectionStart = $script:terminalBox.TextLength
                            $script:terminalBox.ScrollToCaret()
                        }
                    }
                } catch {
                    # Silently ignore log fetch errors
                }
            }

            # Check installation progress by looking for the marker file
            $maxWaitTime = 300  # 5 minutes
            $waitedTime = 0
            $checkInterval = 3  # Check more frequently for better UI updates

            while ($waitedTime -lt $maxWaitTime) {
                # Update terminal display with latest logs
                Update-TerminalDisplay
                [System.Windows.Forms.Application]::DoEvents()

                # Check if installation completed - use sh -c to properly handle shell operators
                # Use "|| true" to ensure exit code 0 even when file doesn't exist (prevents error spam in logs)
                $checkInstallCmd = 'exec ai-cli sh -c "test -f /home/' + $state.UserName + '/.cli_tools_installed && echo INSTALLED || true"'
                $checkResult = Run-Process-UI -file 'docker' -arguments $checkInstallCmd -progressBar $null -statusLabel $null

                if ($checkResult.Ok -and $checkResult.StdOut -match 'INSTALLED') {
                    Write-Host "[SUCCESS] CLI tools installation completed!" -ForegroundColor Green
                    $script:lblCurrentTool.Text = 'Installation complete!'
                    $script:terminalBox.AppendText("`r`n>> INSTALLATION COMPLETE!`r`n")
                    $script:terminalBox.SelectionStart = $script:terminalBox.TextLength
                    $script:terminalBox.ScrollToCaret()
                    $progress.Value = 100
                    break
                }

                # Poll for current tool status and update progress based on which tool is installing
                $statusCmd = 'exec ai-cli sh -c "cat /home/' + $state.UserName + '/.cli_install_status 2>/dev/null || true"'
                $statusResult = Run-Process-UI -file 'docker' -arguments $statusCmd -progressBar $null -statusLabel $null
                if ($statusResult.Ok -and $statusResult.StdOut.Trim()) {
                    $parts = $statusResult.StdOut.Trim().Split('|')
                    if ($parts.Count -ge 2) {
                        $toolName = $parts[0]
                        $pkgMgr = $parts[1]
                        $script:lblCurrentTool.Text = "Installing $toolName via $pkgMgr..."
                        Write-Host "[STATUS] Installing: $toolName ($pkgMgr)" -ForegroundColor Cyan

                        # Update progress based on which tool is currently installing (5 tools total)
                        $toolProgress = switch ($toolName) {
                            'GitHub CLI' { 20 }
                            'Claude Code CLI' { 40 }
                            'Google Gemini CLI' { 60 }
                            'OpenAI Python SDK' { 80 }
                            'OpenAI Codex CLI' { 95 }
                            default { $progress.Value }  # Keep current if unknown
                        }
                        $progress.Value = $toolProgress
                    }
                }
                [System.Windows.Forms.Application]::DoEvents()

                $status.Text = "Installing CLI tools... ($([Math]::Round($waitedTime/60, 1)) minutes elapsed)"

                Start-Sleep -Seconds $checkInterval
                $waitedTime += $checkInterval
            }

            # Final log update
            Update-TerminalDisplay
            [System.Windows.Forms.Application]::DoEvents()

            if ($waitedTime -ge $maxWaitTime) {
                Write-Host "[WARNING] Installation is taking longer than expected, but will continue in background" -ForegroundColor Yellow
                $script:terminalBox.AppendText("`r`n>> Installation taking longer than expected, continuing in background...`r`n")
            }

            # Verify at least the core tools are available
            $status.Text = 'Verifying core CLI tools...'
            Write-Host "[INFO] Verifying core CLI tools installation..." -ForegroundColor Cyan

            # Test 1: Check if claude command exists
            $validateClaude = 'exec ai-cli bash -c "which claude && echo \"Claude found\""'
            $r3a = Run-Process-UI -file 'docker' -arguments $validateClaude -progressBar $null -statusLabel $null

            if ($r3a.Ok -and $r3a.StdOut -match 'Claude found') {
                Write-Host "[SUCCESS] Claude CLI verified" -ForegroundColor Green
            } else {
                Write-Host "[WARNING] Claude CLI not found yet, will be installed in background" -ForegroundColor Yellow
            }

            # Test 2: Check if GitHub CLI exists
            $validateGH = 'exec ai-cli bash -c "which gh && echo \"GitHub CLI found\""'
            $r3b = Run-Process-UI -file 'docker' -arguments $validateGH -progressBar $null -statusLabel $null

            if ($r3b.Ok -and $r3b.StdOut -match 'GitHub CLI found') {
                Write-Host "[SUCCESS] GitHub CLI verified" -ForegroundColor Green
            } else {
                Write-Host "[INFO] GitHub CLI will be installed in background" -ForegroundColor Yellow
            }

            # Test 3: Verify user has sudo access with NOPASSWD
            Write-Host "[INFO] Verifying user sudo privileges..." -ForegroundColor Cyan
            $userSudoTest = 'exec -u ' + $state.UserName + ' ai-cli sudo -n whoami'
            $r3c = Run-Process-UI -file 'docker' -arguments $userSudoTest -progressBar $null -statusLabel $null

            if ($r3c.Ok -and $r3c.StdOut -match 'root') {
                Write-Host "[SUCCESS] User has passwordless sudo access" -ForegroundColor Green
            } else {
                Write-Host "[WARNING] Sudo test inconclusive, but this may be normal" -ForegroundColor Yellow
            }

            Write-Host '[SUCCESS] Installation complete!' -ForegroundColor Green
            $status.Text = 'system ready'
            $script:current++; Show-Page $script:current
        }
        5 {
            # Install CLI Tools page - this page auto-advances via case 3's flow
            # If user somehow clicks Next directly, just show a message
            Write-Host "[INFO] Install page - process is handled automatically" -ForegroundColor Yellow
            $status.Text = 'Installation is automatic - please wait...'
        }
        6 {
            # Codex auth page - only advance if setup was done or skipped
            if ($script:codexSetupDone) {
                $script:current++; Show-Page $script:current
            } else {
                # User clicked Next without setting up or skipping - remind them
                Show-Error "Please click 'Setup Codex Auth' to configure Codex, or 'Skip' to continue without it."
            }
        }
        7 {
            Write-Host "[INFO] User clicked Finish - closing wizard" -ForegroundColor Green
            $form.Close()
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        }
    }
})

# Display startup banner
Clear-Host
Write-Host ""
if ($script:IsDevMode) {
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host "    AI CLI DOCKER SETUP :: [DEV MODE]                          " -ForegroundColor Magenta
    Write-Host "    No destructive operations will be performed                " -ForegroundColor Magenta
    Write-Host "================================================================" -ForegroundColor Magenta
} else {
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "    AI CLI DOCKER SETUP :: MATRIX PROTOCOL v1.0                " -ForegroundColor Green
    Write-Host "    [SYSTEM ONLINE] Running automatic pre-flight checks        " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
}
Write-Host ""

# Automatic pre-flight checks
Write-Host "[PRE-FLIGHT] Running automatic system checks..." -ForegroundColor Cyan
Write-Host ""

# DEV MODE: Skip line endings and image checks, but NOT container protection
if ($script:IsDevMode) {
    Write-Host "[DEV MODE] Skipping line ending and image checks" -ForegroundColor Magenta
    $lineEndingsFixed = $false
} else {
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
}

# 2. Check if old container exists - PROTECT IT!
Write-Host "[CHECK 2/3] Checking for existing containers..." -ForegroundColor Cyan
$existingContainer = docker ps -a --filter "name=ai-cli" --format "{{.Names}}" 2>$null
if ($existingContainer -eq "ai-cli") {
    if ($script:IsDevMode) {
        # DEV MODE: Skip the warning entirely - we never delete in DEV MODE
        Write-Host "[DEV MODE] Existing container found - preserving it (no warning needed)" -ForegroundColor Magenta
        Write-Host "[DEV MODE] Container will be reused for testing" -ForegroundColor Magenta
    } else {
        # Normal mode: Show warning and ask user
        Write-Host "[WARNING] Found existing ai-cli container with your data!" -ForegroundColor Yellow
        Write-Host "[PROTECTION] Container contains your Claude authentication and settings" -ForegroundColor Yellow
        Write-Host ""

        # Show warning dialog with options
        $result = [System.Windows.Forms.MessageBox]::Show(
            "*** EXISTING CONTAINER DETECTED ***`n`n" +
            "An ai-cli container already exists on your system.`n`n" +
            "This container contains:`n" +
            "  - Your Claude authentication (you won't need to sign in again)`n" +
            "  - Your configuration and settings`n" +
            "  - Persistent data`n`n" +
            "RECOMMENDED: Click 'No' and use 'Launch AI Workspace' instead.`n`n" +
            "Click 'Yes' ONLY if you want to DELETE the existing container and start fresh.`n`n" +
            "Do you want to DELETE the existing container and continue with First Time Setup?",
            "Container Already Exists - Delete?",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Host "[USER CHOICE] User chose to delete existing container" -ForegroundColor Red
            Write-Host "[WARNING] Deleting existing container..." -ForegroundColor Red
            docker stop ai-cli 2>$null | Out-Null
            docker rm ai-cli 2>$null | Out-Null
            Write-Host "[SUCCESS] Old container removed" -ForegroundColor Green
        } else {
            Write-Host "[USER CHOICE] User cancelled - keeping existing container" -ForegroundColor Green
            Write-Host "[INFO] Please use 'Launch AI Workspace' to access your existing container" -ForegroundColor Cyan
            [System.Windows.Forms.MessageBox]::Show(
                "Setup cancelled - your existing container is safe!`n`n" +
                "To access your container, please use 'Launch AI Workspace' button instead of 'First Time Setup'.`n`n" +
                "Your Claude authentication and all settings are preserved.",
                "Setup Cancelled",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            exit 2  # Exit code 2 = user cancelled (not an error)
        }
    }
} else {
    Write-Host "[OK] No existing container found" -ForegroundColor Green
}
Write-Host ""

# 3. If line endings were fixed, remove old image to force rebuild (skip in DEV mode)
if (-not $script:IsDevMode) {
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
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  WIZARD READY - Opening window now..." -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
$result = $form.ShowDialog()
Write-Host ""
Write-Host "[SHUTDOWN] Wizard closed" -ForegroundColor Yellow

# Exit with appropriate code based on dialog result
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "[SUCCESS] Setup completed successfully - exiting with code 0" -ForegroundColor Green
    exit 0  # Success
} else {
    Write-Host "[INFO] Setup exited without completion - exiting with code 1" -ForegroundColor Yellow
    exit 1  # Not completed
}

