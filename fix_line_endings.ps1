# fix_line_endings.ps1 - Convert shell scripts to Unix LF line endings

$scriptPath = $PSScriptRoot
$files = @('entrypoint.sh', 'setup.sh', 'claude_wrapper.sh')

Write-Host "================================================================" -ForegroundColor Green
Write-Host "         FIXING LINE ENDINGS FOR LINUX SCRIPTS                  " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

foreach ($file in $files) {
    $filePath = Join-Path $scriptPath $file

    if (Test-Path $filePath) {
        Write-Host "[INFO] Processing: $file" -ForegroundColor Cyan

        # Read file content
        $content = Get-Content $filePath -Raw

        # Check if file has Windows line endings
        if ($content -match "`r`n") {
            Write-Host "  [FIXING] Converting CRLF -> LF" -ForegroundColor Yellow

            # Replace Windows line endings (CRLF) with Unix line endings (LF)
            $content = $content -replace "`r`n", "`n"

            # Write back with Unix line endings (UTF-8 without BOM)
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)

            Write-Host "  [SUCCESS] Fixed: $file" -ForegroundColor Green
        } else {
            Write-Host "  [OK] Already has Unix line endings" -ForegroundColor Green
        }
    } else {
        Write-Host "  [WARNING] File not found: $file" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "                 LINE ENDINGS FIXED!                            " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Remove the old container: docker stop ai-cli ; docker rm ai-cli" -ForegroundColor Yellow
Write-Host "2. Rebuild the image: docker compose build --no-cache" -ForegroundColor Yellow
Write-Host "3. Run the wizard again" -ForegroundColor Yellow
Write-Host ""

