# build_complete_exe.ps1 - Creates a single self-contained executable

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "   BUILDING COMPLETE AI DOCKER SETUP EXECUTABLE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

# Check if ps2exe is installed
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "[INFO] Installing ps2exe module..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Scope CurrentUser -Force
    Write-Host "[SUCCESS] ps2exe installed" -ForegroundColor Green
    Write-Host ""
}

# Read all file contents
Write-Host "[1/4] Reading source files..." -ForegroundColor Cyan

$filesToEmbed = @(
   "..\setup_wizard.ps1",
   "..\launch_claude.ps1",
   "..\..\docker\docker-compose.yml",
   "..\..\docker\Dockerfile",
   "..\..\docker\entrypoint.sh",
   "..\..\docker\claude_wrapper.sh",
   "..\..\docker\install_cli_tools.sh",
   "..\..\docker\auto_update.sh",
   "..\..\docker\configure_tools.sh",
   "..\fix_line_endings.ps1",
   "..\..\.gitattributes",
   "..\..\README.md",
   "..\..\docs\USER_MANUAL.md",
   "..\..\docs\QUICK_REFERENCE.md",
   "..\..\docs\CLI_TOOLS_GUIDE.md",
   "..\..\tests\TESTING_CHECKLIST.md"
)

# Check all files exist before proceeding
$missingFiles = @()
foreach ($file in $filesToEmbed) {
    if (-not (Test-Path $file)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host "  ERROR Missing required files:" -ForegroundColor Red
    foreach ($file in $missingFiles) {
        Write-Host "    - $file" -ForegroundColor Red
    }
    exit 1
}

# Read all files
$files = @{}
foreach ($file in $filesToEmbed) {
    try {
        $files[$file] = Get-Content $file -Raw -ErrorAction Stop
        Write-Host "    Read: $file" -ForegroundColor Gray
    } catch {
        Write-Host "  ERROR Failed to read $file : $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  OK Read $($files.Count) files" -ForegroundColor Green

# Create the bundled script
Write-Host "[2/4] Creating bundled script..." -ForegroundColor Cyan

# Template is in scripts/ directory (one level up)
$templatePath = "..\AI_Docker_Complete.ps1"
$bundledScript = Get-Content $templatePath -Raw

# Replace placeholders with actual content (Base64 encoded)
foreach ($fileName in $files.Keys) {
    # Extract just the filename without path for cleaner placeholders
    $justFileName = Split-Path -Leaf $fileName

    # Normalize the filename: replace dots and hyphens with underscores
    $normalizedName = $justFileName.Replace('.', '_').Replace('-', '_').ToUpper()
    $placeholder = $normalizedName + "_BASE64_HERE"

    # Convert content to Base64
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($files[$fileName])
    $base64Content = [System.Convert]::ToBase64String($bytes)

    # Use literal replacement to avoid regex issues
    $bundledScript = $bundledScript.Replace($placeholder, $base64Content)

    Write-Host "    Embedded: $fileName -> $placeholder" -ForegroundColor Gray
}

# Save the bundled script to project root
$projectRoot = Join-Path $PSScriptRoot "..\..\"
$bundledScriptPath = Join-Path $projectRoot "AI_Docker_Complete_Bundled.ps1"
$bundledScript | Out-File $bundledScriptPath -Encoding UTF8

# Validate that all placeholders were replaced
$bundledContent = Get-Content $bundledScriptPath -Raw
$unreplacedCount = 0

# Check for any remaining BASE64_HERE placeholders
if ($bundledContent -match "([A-Z_]+_BASE64_HERE)") {
    $unreplacedPlaceholders = [regex]::Matches($bundledContent, "([A-Z_]+_BASE64_HERE)")
    $unreplacedCount = $unreplacedPlaceholders.Count

    if ($unreplacedCount -gt 0) {
        Write-Host "  WARNING Found $unreplacedCount unreplaced placeholders:" -ForegroundColor Yellow
        foreach ($match in $unreplacedPlaceholders | Select-Object -First 3) {
            Write-Host "    $($match.Value)" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  This indicates the build may have failed. Continue anyway? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response -ne 'Y' -and $response -ne 'y') {
            Write-Host "  Build cancelled" -ForegroundColor Red
            Remove-Item $bundledScriptPath -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }
}

Write-Host "  OK Created AI_Docker_Complete_Bundled.ps1" -ForegroundColor Green

# Compile to exe
Write-Host "[3/4] Compiling to executable..." -ForegroundColor Cyan

# Output to project root
$exePath = Join-Path $projectRoot "AI_Docker_Manager.exe"

try {
    Invoke-ps2exe `
        -inputFile $bundledScriptPath `
        -outputFile $exePath `
        -title "AI Docker Manager" `
        -description "Complete AI CLI Docker Setup System" `
        -company "Your Company" `
        -product "AI Docker CLI Setup" `
        -version "2.0.0.0" `
        -noConsole

    if (Test-Path $exePath) {
        Write-Host "  OK AI_Docker_Manager.exe created successfully!" -ForegroundColor Green

        $fileSize = (Get-Item $exePath).Length / 1MB
        Write-Host "  Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
    } else {
        throw "EXE file was not created"
    }
} catch {
    Write-Host "  ERROR Compilation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Clean up temporary bundled script
Write-Host "[4/4] Cleaning up..." -ForegroundColor Cyan
Remove-Item $bundledScriptPath -Force -ErrorAction SilentlyContinue
Write-Host "  OK Removed temporary files" -ForegroundColor Green

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "                BUILD COMPLETE!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output: $exePath" -ForegroundColor Cyan
Write-Host ""
Write-Host "This executable contains:" -ForegroundColor Cyan
Write-Host "  OK Setup Wizard" -ForegroundColor Green
Write-Host "  OK Claude Launcher" -ForegroundColor Green
Write-Host "  OK Docker configuration files" -ForegroundColor Green
Write-Host "  OK All shell scripts" -ForegroundColor Green
Write-Host "  OK Complete documentation" -ForegroundColor Green
Write-Host ""
Write-Host "Users can:" -ForegroundColor Cyan
Write-Host "  1. Download AI_Docker_Manager.exe" -ForegroundColor Yellow
Write-Host "  2. Run it (extracts files on first run)" -ForegroundColor Yellow
Write-Host "  3. Click First Time Setup to install" -ForegroundColor Yellow
Write-Host "  4. Click Launch Claude CLI for daily use" -ForegroundColor Yellow
Write-Host ""
Write-Host "Ready for distribution!" -ForegroundColor Green
Write-Host ""

