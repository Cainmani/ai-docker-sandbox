# run_tests.ps1 - Comprehensive test suite for AI Docker Manager
# Run this before distributing to ensure all components work correctly

param(
    [switch]$SkipDocker,  # Skip tests that require Docker running
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0

# Color functions
function Write-TestHeader($text) {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Write-TestPass($text) {
    Write-Host "[PASS] $text" -ForegroundColor Green
    $script:TestsPassed++
}

function Write-TestFail($text, $details = "") {
    Write-Host "[FAIL] $text" -ForegroundColor Red
    if ($details) {
        Write-Host "       $details" -ForegroundColor Yellow
    }
    $script:TestsFailed++
}

function Write-TestSkip($text, $reason = "") {
    Write-Host "[SKIP] $text" -ForegroundColor Yellow
    if ($reason) {
        Write-Host "       Reason: $reason" -ForegroundColor Gray
    }
    $script:TestsSkipped++
}

function Write-TestInfo($text) {
    if ($Verbose) {
        Write-Host "       $text" -ForegroundColor Gray
    }
}

# Test function wrapper
function Test-Assertion {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [string]$ErrorMessage = "Test failed"
    )

    try {
        $result = & $Test
        if ($result) {
            Write-TestPass $Name
            return $true
        } else {
            Write-TestFail $Name $ErrorMessage
            return $false
        }
    } catch {
        Write-TestFail $Name "$ErrorMessage - Exception: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# TEST SUITE START
# ============================================================================

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  AI DOCKER MANAGER - AUTOMATED TEST SUITE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Testing started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# PHASE 1: FILE EXISTENCE TESTS
# ============================================================================

Write-TestHeader "PHASE 1: FILE EXISTENCE TESTS"

# Get the project root directory (parent of tests/)
$projectRoot = Split-Path -Parent $PSScriptRoot

$requiredFiles = @(
    (Join-Path $projectRoot 'scripts\setup_wizard.ps1'),
    (Join-Path $projectRoot 'scripts\launch_claude.ps1'),
    (Join-Path $projectRoot 'scripts\AI_Docker_Launcher.ps1'),
    (Join-Path $projectRoot 'scripts\AI_Docker_Complete.ps1'),
    (Join-Path $projectRoot 'docker\docker-compose.yml'),
    (Join-Path $projectRoot 'docker\Dockerfile'),
    (Join-Path $projectRoot 'docker\entrypoint.sh'),
    (Join-Path $projectRoot 'docker\claude_wrapper.sh'),
    (Join-Path $projectRoot 'scripts\fix_line_endings.ps1'),
    (Join-Path $projectRoot '.gitattributes'),
    (Join-Path $projectRoot 'README.md'),
    (Join-Path $projectRoot 'docs\USER_MANUAL.md'),
    (Join-Path $projectRoot 'docs\QUICK_REFERENCE.md'),
    (Join-Path $projectRoot 'tests\TESTING_CHECKLIST.md'),
    (Join-Path $projectRoot 'scripts\build\build_complete_exe.ps1'),
    (Join-Path $projectRoot 'scripts\build\BUILD_NOW.bat')
)

foreach ($file in $requiredFiles) {
    Test-Assertion "File exists: $file" {
        Test-Path $file
    } "File not found"
}

# ============================================================================
# PHASE 2: FILE CONTENT VALIDATION
# ============================================================================

Write-TestHeader "PHASE 2: FILE CONTENT VALIDATION"

# Test shell scripts have LF line endings
$shellScripts = @(
    (Join-Path $projectRoot 'docker\entrypoint.sh'),
    (Join-Path $projectRoot 'docker\claude_wrapper.sh')
)
foreach ($scriptPath in $shellScripts) {
    $scriptName = Split-Path -Leaf $scriptPath
    Test-Assertion "Shell script has LF endings: $scriptName" {
        if (Test-Path $scriptPath) {
            $content = Get-Content $scriptPath -Raw
            -not ($content -match "`r`n")
        } else {
            $false
        }
    } "Shell script has CRLF line endings (will fail in Linux)"
}

# Test PowerShell scripts are valid
$psScripts = @(
    (Join-Path $projectRoot 'scripts\setup_wizard.ps1'),
    (Join-Path $projectRoot 'scripts\launch_claude.ps1'),
    (Join-Path $projectRoot 'scripts\AI_Docker_Launcher.ps1')
)
foreach ($scriptPath in $psScripts) {
    $scriptName = Split-Path -Leaf $scriptPath
    Test-Assertion "PowerShell script is valid: $scriptName" {
        if (Test-Path $scriptPath) {
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$null)
            $true
        } else {
            $false
        }
    } "Syntax error in PowerShell script"
}

# Test docker-compose.yml is valid YAML
$composeFile = Join-Path $projectRoot 'docker\docker-compose.yml'
Test-Assertion "docker-compose.yml is valid YAML" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        # Basic YAML validation
        ($content -match 'services:') -and ($content -match 'volumes:')
    } else {
        $false
    }
} "Invalid YAML structure"

# Test Dockerfile contains required components
$dockerFile = Join-Path $projectRoot 'docker\Dockerfile'
Test-Assertion "Dockerfile contains FROM ubuntu" {
    if (Test-Path $dockerFile) {
        $content = Get-Content $dockerFile -Raw
        $content -match 'FROM ubuntu'
    } else {
        $false
    }
} "Dockerfile missing base image"

Test-Assertion "Dockerfile installs Node.js and npm" {
    if (Test-Path $dockerFile) {
        $content = Get-Content $dockerFile -Raw
        ($content -match 'nodejs') -and ($content -match 'npm')
    } else {
        $false
    }
} "Dockerfile missing Node.js/npm"

# ============================================================================
# PHASE 3: CONFIGURATION VALIDATION
# ============================================================================

Write-TestHeader "PHASE 3: CONFIGURATION VALIDATION"

# Test docker-compose.yml uses correct container name
Test-Assertion "docker-compose.yml uses 'ai-cli' container name" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        $content -match 'container_name:\s*ai-cli'
    } else {
        $false
    }
} "Container name not set to 'ai-cli'"

# Test docker-compose.yml has named volume for claude config
Test-Assertion "docker-compose.yml has claude-config volume" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        $content -match 'claude-config:'
    } else {
        $false
    }
} "Named volume for Claude config missing"

# Test entrypoint.sh creates user with sudo privileges
$entrypointFile = Join-Path $projectRoot 'docker\entrypoint.sh'
Test-Assertion "entrypoint.sh grants passwordless sudo" {
    if (Test-Path $entrypointFile) {
        $content = Get-Content $entrypointFile -Raw
        $content -match 'NOPASSWD:ALL'
    } else {
        $false
    }
} "Passwordless sudo not configured"

# Test entrypoint.sh fixes .claude directory permissions (CRITICAL FIX)
Test-Assertion "entrypoint.sh sets ownership of .claude directory" {
    if (Test-Path $entrypointFile) {
        $content = Get-Content $entrypointFile -Raw
        $content -match 'chown.*\.claude'
    } else {
        $false
    }
} "CRITICAL: .claude directory ownership not set (will cause permission errors)"

# ============================================================================
# PHASE 4: SETUP WIZARD VALIDATION
# ============================================================================

Write-TestHeader "PHASE 4: SETUP WIZARD VALIDATION"

# Test setup wizard uses correct docker compose commands
$setupWizardFile = Join-Path $projectRoot 'scripts\setup_wizard.ps1'
Test-Assertion "setup_wizard.ps1 uses 'compose build' (not with -f flag)" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        ($content -match "compose build") -and (-not ($content -match 'compose -f "\$'))
    } else {
        $false
    }
} "CRITICAL: Docker compose command uses old quoted path format"

# Test setup wizard has validation
Test-Assertion "setup_wizard.ps1 validates Claude installation" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        $content -match 'Validating Claude CLI installation'
    } else {
        $false
    }
} "CRITICAL: No post-installation validation"

# Test setup wizard has container protection
Test-Assertion "setup_wizard.ps1 protects existing containers" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        $content -match 'EXISTING CONTAINER DETECTED'
    } else {
        $false
    }
} "Container protection warning missing"

# Test setup wizard has cancel confirmation
Test-Assertion "setup_wizard.ps1 confirms cancellation during critical steps" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        $content -match 'Are you sure you want to cancel'
    } else {
        $false
    }
} "Cancel confirmation missing"

# ============================================================================
# PHASE 5: BUILD SYSTEM VALIDATION
# ============================================================================

Write-TestHeader "PHASE 5: BUILD SYSTEM VALIDATION"

# Test build script includes all documentation
$buildScriptFile = Join-Path $projectRoot 'scripts\build\build_complete_exe.ps1'
Test-Assertion "build_complete_exe.ps1 includes USER_MANUAL.md" {
    if (Test-Path $buildScriptFile) {
        $content = Get-Content $buildScriptFile -Raw
        $content -match 'USER_MANUAL.md'
    } else {
        $false
    }
} "USER_MANUAL.md not included in build"

Test-Assertion "build_complete_exe.ps1 includes QUICK_REFERENCE.md" {
    if (Test-Path $buildScriptFile) {
        $content = Get-Content $buildScriptFile -Raw
        $content -match 'QUICK_REFERENCE.md'
    } else {
        $false
    }
} "QUICK_REFERENCE.md not included in build"

# Test AI_Docker_Complete.ps1 has placeholders for all files
$completeTemplateFile = Join-Path $projectRoot 'scripts\AI_Docker_Complete.ps1'
Test-Assertion "AI_Docker_Complete.ps1 has placeholder for USER_MANUAL.md" {
    if (Test-Path $completeTemplateFile) {
        $content = Get-Content $completeTemplateFile -Raw
        $content -match 'USER_MANUAL_MD_BASE64_HERE'
    } else {
        $false
    }
} "USER_MANUAL.md placeholder missing in template"

# ============================================================================
# PHASE 6: DOCKER TESTS (Optional - requires Docker running)
# ============================================================================

Write-TestHeader "PHASE 6: DOCKER ENVIRONMENT TESTS"

if ($SkipDocker) {
    Write-TestSkip "Docker executable check" "Docker tests skipped (-SkipDocker flag)"
    Write-TestSkip "Docker running check" "Docker tests skipped (-SkipDocker flag)"
    Write-TestSkip "Docker version check" "Docker tests skipped (-SkipDocker flag)"
} else {
    # Test Docker is installed
    Test-Assertion "Docker executable exists" {
        $null -ne (Get-Command docker -ErrorAction SilentlyContinue)
    } "Docker not found in PATH"

    # Test Docker is running
    $dockerRunning = $false
    try {
        $null = docker info 2>$null
        $dockerRunning = $LASTEXITCODE -eq 0
    } catch {
        $dockerRunning = $false
    }

    Test-Assertion "Docker daemon is running" {
        $dockerRunning
    } "Docker Desktop not running"

    # Test Docker version
    if ($dockerRunning) {
        Test-Assertion "Docker version is acceptable" {
            try {
                $version = docker --version
                $version -match 'Docker version'
            } catch {
                $false
            }
        } "Cannot determine Docker version"
    } else {
        Write-TestSkip "Docker version check" "Docker not running"
    }

    # Test docker compose is available
    if ($dockerRunning) {
        Test-Assertion "Docker compose is available" {
            try {
                $null = docker compose version 2>$null
                $LASTEXITCODE -eq 0
            } catch {
                $false
            }
        } "Docker compose not available"
    } else {
        Write-TestSkip "Docker compose check" "Docker not running"
    }
}

# ============================================================================
# PHASE 7: DOCUMENTATION QUALITY TESTS
# ============================================================================

Write-TestHeader "PHASE 7: DOCUMENTATION QUALITY TESTS"

# Test USER_MANUAL.md has key sections
$userManualFile = Join-Path $projectRoot 'docs\USER_MANUAL.md'
Test-Assertion "USER_MANUAL.md contains 'First Time Setup' section" {
    if (Test-Path $userManualFile) {
        $content = Get-Content $userManualFile -Raw
        $content -match '## First Time Setup'
    } else {
        $false
    }
} "USER_MANUAL.md missing critical section"

Test-Assertion "USER_MANUAL.md contains 'First Time Authentication' section" {
    if (Test-Path $userManualFile) {
        $content = Get-Content $userManualFile -Raw
        $content -match '## First Time Authentication'
    } else {
        $false
    }
} "USER_MANUAL.md missing authentication guide"

Test-Assertion "USER_MANUAL.md contains 'Troubleshooting' section" {
    if (Test-Path $userManualFile) {
        $content = Get-Content $userManualFile -Raw
        $content -match '## Troubleshooting'
    } else {
        $false
    }
} "USER_MANUAL.md missing troubleshooting section"

# Test README.md links to documentation
$readmeFile = Join-Path $projectRoot 'README.md'
Test-Assertion "README.md links to USER_MANUAL.md" {
    if (Test-Path $readmeFile) {
        $content = Get-Content $readmeFile -Raw
        $content -match 'USER_MANUAL.md'
    } else {
        $false
    }
} "README.md missing link to user manual"

# ============================================================================
# TEST RESULTS SUMMARY
# ============================================================================

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  TEST RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tests Passed:  " -NoNewline -ForegroundColor Gray
Write-Host $script:TestsPassed -ForegroundColor Green
Write-Host "Tests Failed:  " -NoNewline -ForegroundColor Gray
Write-Host $script:TestsFailed -ForegroundColor Red
Write-Host "Tests Skipped: " -NoNewline -ForegroundColor Gray
Write-Host $script:TestsSkipped -ForegroundColor Yellow
Write-Host ""

$totalTests = $script:TestsPassed + $script:TestsFailed
$passRate = if ($totalTests -gt 0) { [math]::Round(($script:TestsPassed / $totalTests) * 100, 2) } else { 0 }

Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { 'Green' } elseif ($passRate -ge 90) { 'Yellow' } else { 'Red' })
Write-Host ""
Write-Host "Testing completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# Exit code based on results
if ($script:TestsFailed -eq 0) {
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "  ALL TESTS PASSED - READY FOR DISTRIBUTION" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    exit 0
} else {
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "  TESTS FAILED - DO NOT DISTRIBUTE" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the failing tests before distributing AI_Docker_Manager.exe" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
