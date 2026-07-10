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
    (Join-Path $projectRoot 'scripts\uninstall.ps1'),
    (Join-Path $projectRoot 'docker\docker-compose.yml'),
    (Join-Path $projectRoot 'docker\docker-compose.mobile.yml'),
    (Join-Path $projectRoot 'docker\docker-compose.ca.yml'),
    (Join-Path $projectRoot 'docker\Dockerfile'),
    (Join-Path $projectRoot 'docker\entrypoint.sh'),
    (Join-Path $projectRoot 'docker\install_cli_tools.sh'),
    (Join-Path $projectRoot 'docker\auto_update.sh'),
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
    (Join-Path $projectRoot 'docker\install_cli_tools.sh'),
    (Join-Path $projectRoot 'docker\auto_update.sh')
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
    (Join-Path $projectRoot 'scripts\AI_Docker_Launcher.ps1'),
    (Join-Path $projectRoot 'scripts\uninstall.ps1'),
    (Join-Path $projectRoot 'scripts\docker_helpers.ps1'),
    (Join-Path $projectRoot 'scripts\env_utils.ps1'),
    (Join-Path $projectRoot 'scripts\setup_utils.ps1')
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

Test-Assertion "Dockerfile installs Node.js (including npm)" {
    if (Test-Path $dockerFile) {
        $content = Get-Content $dockerFile -Raw
        ($content -match 'deb\.nodesource\.com/setup_22\.x') -and
        ($content -match 'apt-get install -y nodejs')
    } else {
        $false
    }
} "Dockerfile missing NodeSource Node.js package (which includes npm)"

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

# Test docker-compose.yml has fixed project and image identity
Test-Assertion "docker-compose.yml pins project name 'ai-docker'" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        $content -match '(?m)^name:\s*ai-docker\s*$'
    } else {
        $false
    }
} "Compose project name not fixed (identity would depend on folder name)"

Test-Assertion "docker-compose.yml pins image name 'ai-docker-cli'" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        $content -match 'image:\s*ai-docker-cli:latest'
    } else {
        $false
    }
} "Image name not fixed to ai-docker-cli:latest"

# Base compose file must NOT publish SSH/Mosh ports - those live in the mobile override
Test-Assertion "docker-compose.yml does not publish SSH/Mosh ports" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        -not ($content -match '"\$\{SSH_PORT') -and -not ($content -match '\$\{MOSH_PORT_START[^}]*\}-\$\{MOSH_PORT_END[^}]*\}:')
    } else {
        $false
    }
} "SSH/Mosh port mappings must only exist in docker-compose.mobile.yml"

$mobileComposeFile = Join-Path $projectRoot 'docker\docker-compose.mobile.yml'
Test-Assertion "docker-compose.mobile.yml exists and publishes SSH/Mosh ports" {
    if (Test-Path $mobileComposeFile) {
        $content = Get-Content $mobileComposeFile -Raw
        ($content -match 'SSH_PORT') -and ($content -match 'MOSH_PORT_START') -and ($content -match '/udp')
    } else {
        $false
    }
} "Mobile access override file missing or incomplete"

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

# Test setup wizard validates the core Claude command after installation.
Test-Assertion "setup_wizard.ps1 validates Claude installation" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        ($content -match 'Verifying core CLI tools installation') -and
        ($content -match 'which claude') -and
        ($content -match 'Claude CLI verified')
    } else {
        $false
    }
} "CRITICAL: No post-installation Claude command validation"

# Test setup wizard removes the obsolete persistent force-reinstall flag.
Test-Assertion "setup_wizard.ps1 removes stale FORCE_CLI_REINSTALL from .env" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        ($content -match 'Remove-Env(Key|Value)[^\r\n]*FORCE_CLI_REINSTALL') -and
        (-not ($content -match '\$env:FORCE_CLI_REINSTALL\s*=')) -and
        (-not ($content -match 'Add-Content[^\r\n]*FORCE_CLI_REINSTALL'))
    } else {
        $false
    }
} "FORCE_CLI_REINSTALL must be removed from .env and never passed to Compose"

# Test setup wizard uses the fixed image name (no legacy folder-derived names)
Test-Assertion "setup_wizard.ps1 checks the fixed image name" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        ($content -match 'AiDockerImageName') -and (-not ($content -match "arguments 'images docker-files-ai"))
    } else {
        $false
    }
} "Setup wizard still references the folder-derived legacy image name"

# Test setup wizard uses shared readiness helper instead of fixed sleeps
Test-Assertion "setup_wizard.ps1 uses Wait-ContainerReady" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        $content -match 'Wait-ContainerReady'
    } else {
        $false
    }
} "Setup wizard should poll container readiness via Wait-ContainerReady"

# Test setup wizard writes .env next to the compose file (canonical location)
Test-Assertion "setup_wizard.ps1 uses canonical .env location (docker folder)" {
    if (Test-Path $setupWizardFile) {
        $content = Get-Content $setupWizardFile -Raw
        $content -match "envPath\s*=\s*Join-Path\s+\`$dockerPath\s+'\.env'"
    } else {
        $false
    }
} ".env must live next to docker-compose.yml so compose variable substitution works"

# Test uninstall script exists with safe defaults
$uninstallFile = Join-Path $projectRoot 'scripts\uninstall.ps1'
Test-Assertion "uninstall.ps1 exists" {
    Test-Path $uninstallFile
} "Supported uninstall script missing"

Test-Assertion "uninstall.ps1 keeps volumes by default (opt-in -RemoveVolumes)" {
    if (Test-Path $uninstallFile) {
        $content = Get-Content $uninstallFile -Raw
        ($content -match '\[switch\]\$RemoveVolumes') -and ($content -match '\[switch\]\$RemoveAppData')
    } else {
        $false
    }
} "Uninstall must not delete user data volumes by default"

Test-Assertion "uninstall.ps1 never touches the AI_Work workspace" {
    if (Test-Path $uninstallFile) {
        $content = Get-Content $uninstallFile -Raw
        -not ($content -match 'Remove-Item[^\r\n]*AI_Work')
    } else {
        $false
    }
} "Uninstall must never delete the user workspace folder"

# Test Vibe Kanban launcher validates the port before shell interpolation
Test-Assertion "launch_vibe_kanban.ps1 validates VIBE_KANBAN_PORT" {
    $vibeLauncher = Join-Path $projectRoot 'scripts\launch_vibe_kanban.ps1'
    if (Test-Path $vibeLauncher) {
        $content = Get-Content $vibeLauncher -Raw
        $content -match 'Test-ValidPort'
    } else {
        $false
    }
} "Port from .env must be validated before interpolation into bash commands"

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

Test-Assertion "Complete executable packages custom CA override" {
    if ((Test-Path $buildScriptFile) -and (Test-Path $completeTemplateFile)) {
        $buildContent = Get-Content $buildScriptFile -Raw
        $templateContent = Get-Content $completeTemplateFile -Raw
        ($buildContent -match 'docker-compose\.ca\.yml') -and
        ($templateContent -match 'DOCKER_COMPOSE_CA_YML_BASE64_HERE')
    } else {
        $false
    }
} "Custom CA Compose override missing from executable package"

Test-Assertion "Every Dockerfile-copied helper library is packaged" {
    if ((Test-Path $dockerFile) -and (Test-Path $buildScriptFile) -and (Test-Path $completeTemplateFile)) {
        $dockerContent = Get-Content $dockerFile -Raw
        $buildContent = Get-Content $buildScriptFile -Raw
        $templateContent = Get-Content $completeTemplateFile -Raw
        $copiedHelpers = [regex]::Matches($dockerContent, '(?m)^COPY\s+lib/([^\s]+\.sh)\s+') |
            ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        $allPackaged = $copiedHelpers.Count -gt 0
        foreach ($helper in $copiedHelpers) {
            $placeholder = ($helper.Replace('.', '_').Replace('-', '_').ToUpper() + '_BASE64_HERE')
            if (($buildContent -notmatch [regex]::Escape("lib\$helper")) -or
                ($templateContent -notmatch [regex]::Escape($placeholder))) {
                $allPackaged = $false
            }
        }
        $allPackaged
    } else {
        $false
    }
} "A docker/lib helper copied by Dockerfile is absent from the packaged executable"

# ============================================================================
# PHASE 6: VIBE KANBAN INTEGRATION TESTS
# ============================================================================

Write-TestHeader "PHASE 6: VIBE KANBAN INTEGRATION TESTS"

# Test launch_vibe_kanban.ps1 exists
$vibeKanbanLauncher = Join-Path $projectRoot 'scripts\launch_vibe_kanban.ps1'
Test-Assertion "launch_vibe_kanban.ps1 exists" {
    Test-Path $vibeKanbanLauncher
} "Vibe Kanban launcher script not found"

# Test launch_vibe_kanban.ps1 is valid PowerShell
Test-Assertion "launch_vibe_kanban.ps1 is valid PowerShell" {
    if (Test-Path $vibeKanbanLauncher) {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $vibeKanbanLauncher -Raw), [ref]$null)
        $true
    } else {
        $false
    }
} "Syntax error in Vibe Kanban launcher"

# Test launch_vibe_kanban.ps1 uses correct HOST binding
Test-Assertion "launch_vibe_kanban.ps1 uses HOST=0.0.0.0" {
    if (Test-Path $vibeKanbanLauncher) {
        $content = Get-Content $vibeKanbanLauncher -Raw
        $content -match 'HOST=0.0.0.0'
    } else {
        $false
    }
} "HOST binding not configured for container access"

# Test docker-compose.yml has Vibe Kanban port
Test-Assertion "docker-compose.yml exposes Vibe Kanban port" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        $content -match 'VIBE_KANBAN_PORT'
    } else {
        $false
    }
} "Vibe Kanban port not configured"

# Test docker-compose.yml has ports section
Test-Assertion "docker-compose.yml has ports mapping" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        $content -match 'ports:'
    } else {
        $false
    }
} "Port mapping section missing"

# Test docker-compose.yml has vibe-kanban-data volume
Test-Assertion "docker-compose.yml has vibe-kanban-data volume" {
    if (Test-Path $composeFile) {
        $content = Get-Content $composeFile -Raw
        $content -match 'vibe-kanban-data'
    } else {
        $false
    }
} "Vibe Kanban data volume not configured"

# Test install_cli_tools.sh includes Vibe Kanban
$installScript = Join-Path $projectRoot 'docker\install_cli_tools.sh'
Test-Assertion "install_cli_tools.sh installs Vibe Kanban" {
    if (Test-Path $installScript) {
        $content = Get-Content $installScript -Raw
        $content -match 'vibe-kanban'
    } else {
        $false
    }
} "Vibe Kanban not in installation script"

# The updater discovers all installed npm packages dynamically, including Vibe Kanban.
$updateScript = Join-Path $projectRoot 'docker\auto_update.sh'
Test-Assertion "auto_update.sh dynamically checks and updates global npm tools" {
    if (Test-Path $updateScript) {
        $content = Get-Content $updateScript -Raw
        ($content -match 'npm outdated -g') -and
        ($content -match 'npm update -g') -and
        (-not ($content -match 'npm outdated -g[^\r\n]*vibe-kanban'))
    } else {
        $false
    }
} "Updater must discover global npm tools dynamically rather than hardcoding Vibe Kanban"

# Test AI_Docker_Launcher.ps1 has Vibe Kanban button
$launcherFile = Join-Path $projectRoot 'scripts\AI_Docker_Launcher.ps1'
Test-Assertion "AI_Docker_Launcher.ps1 has Vibe Kanban button" {
    if (Test-Path $launcherFile) {
        $content = Get-Content $launcherFile -Raw
        ($content -match 'btnVibeKanban') -and ($content -match 'LAUNCH VIBE KANBAN')
    } else {
        $false
    }
} "Vibe Kanban button not added to launcher"

# Test documentation includes Vibe Kanban
Test-Assertion "CLI_TOOLS_GUIDE.md documents Vibe Kanban" {
    $cliGuide = Join-Path $projectRoot 'docs\CLI_TOOLS_GUIDE.md'
    if (Test-Path $cliGuide) {
        $content = Get-Content $cliGuide -Raw
        $content -match 'Vibe Kanban'
    } else {
        $false
    }
} "Vibe Kanban not documented in CLI guide"

$userManualFile = Join-Path $projectRoot 'docs\USER_MANUAL.md'
Test-Assertion "USER_MANUAL.md documents Vibe Kanban" {
    if (Test-Path $userManualFile) {
        $content = Get-Content $userManualFile -Raw
        $content -match 'Vibe Kanban'
    } else {
        $false
    }
} "Vibe Kanban not documented in user manual"

Test-Assertion "QUICK_REFERENCE.md documents Vibe Kanban" {
    $quickRef = Join-Path $projectRoot 'docs\QUICK_REFERENCE.md'
    if (Test-Path $quickRef) {
        $content = Get-Content $quickRef -Raw
        $content -match 'Vibe Kanban'
    } else {
        $false
    }
} "Vibe Kanban not documented in quick reference"

# ============================================================================
# PHASE 7: DOCKER TESTS (Optional - requires Docker running)
# ============================================================================

Write-TestHeader "PHASE 7: DOCKER ENVIRONMENT TESTS"

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
# PHASE 8: DOCUMENTATION QUALITY TESTS
# ============================================================================

Write-TestHeader "PHASE 8: DOCUMENTATION QUALITY TESTS"

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
