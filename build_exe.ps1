# build_exe.ps1 - Quick script to compile the launcher to EXE

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "           BUILDING AI DOCKER MANAGER EXE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

# Check if ps2exe is installed
$ps2exeInstalled = Get-Module -ListAvailable -Name ps2exe

if (-not $ps2exeInstalled) {
    Write-Host "[INFO] ps2exe module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Scope CurrentUser -Force
    Write-Host "[SUCCESS] ps2exe installed" -ForegroundColor Green
}

# Compile the launcher
Write-Host ""
Write-Host "[COMPILING] Creating AI_Docker_Manager.exe..." -ForegroundColor Cyan

try {
    Invoke-ps2exe `
        -inputFile "AI_Docker_Launcher.ps1" `
        -outputFile "AI_Docker_Manager.exe" `
        -title "AI Docker Manager" `
        -description "AI CLI Docker Management System" `
        -version "1.0.0.0" `
        -noConsole `
        -noError

    if (Test-Path "AI_Docker_Manager.exe") {
        Write-Host "[SUCCESS] EXE created successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Output: AI_Docker_Manager.exe" -ForegroundColor Cyan

        $fileSize = (Get-Item "AI_Docker_Manager.exe").Length / 1MB
        Write-Host "Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
    } else {
        Write-Host "[ERROR] Compilation failed - file not created" -ForegroundColor Red
    }
} catch {
    Write-Host "[ERROR] Compilation failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "                   BUILD COMPLETE!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Test the exe: .\AI_Docker_Manager.exe" -ForegroundColor Yellow
Write-Host "  2. Create distribution package (zip all files)" -ForegroundColor Yellow
Write-Host "  3. Distribute to users" -ForegroundColor Yellow
Write-Host ""

