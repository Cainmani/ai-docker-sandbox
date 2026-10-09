# docker_helpers.ps1 - Shared Docker detection utilities for AI Docker CLI Manager
# Provides Docker executable discovery and daemon health checks.
# Usage: . "$PSScriptRoot\docker_helpers.ps1"
# NOTE: These functions are Windows-only (use Windows paths and -WindowStyle Hidden).
# DEPENDENCY: Requires log_utils.ps1 to be loaded first (for Write-AppLog).

function Find-Docker() {
    Write-AppLog "Finding Docker executable..." "DEBUG"
    # Check if docker is in PATH
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCmd) {
        Write-AppLog "Docker found in PATH: $($dockerCmd.Source)" "DEBUG"
        return $dockerCmd.Source
    }

    # Check common Docker Desktop installation paths
    $possiblePaths = @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe",
        "$env:ProgramW6432\Docker\Docker\resources\bin\docker.exe"
    )

    Write-AppLog "Docker not in PATH, checking common installation paths..." "DEBUG"
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-AppLog "Docker found at: $path" "DEBUG"
            return $path
        }
    }

    Write-AppLog "Docker executable not found" "WARN"
    return $null
}

# Run a docker command with captured output and a hard timeout.
# Returns @{ Success; ExitCode; Output; Error; TimedOut }.
function Invoke-DockerCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [int]$TimeoutSeconds = 60,

        [string]$DockerPath = $null
    )

    $result = @{ Success = $false; ExitCode = -1; Output = ''; Error = ''; TimedOut = $false }

    if (-not $DockerPath) {
        $DockerPath = Find-Docker
    }
    if (-not $DockerPath) {
        $result.Error = 'Docker executable not found'
        Write-AppLog "Invoke-DockerCommand: Docker executable not found" "WARN"
        return $result
    }

    Write-AppLog "Invoke-DockerCommand: docker $($Arguments -join ' ') (timeout: ${TimeoutSeconds}s)" "DEBUG"

    $process = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $DockerPath
        $psi.Arguments = ($Arguments | ForEach-Object {
            '"' + ([regex]::Replace($_, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
        }) -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)

        # Read output asynchronously to avoid deadlock on full pipe buffers
        $stdOutTask = $process.StandardOutput.ReadToEndAsync()
        $stdErrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.TimedOut = $true
            $result.Error = "docker command timed out after ${TimeoutSeconds}s"
            Write-AppLog "Invoke-DockerCommand: timed out after ${TimeoutSeconds}s (docker $($Arguments -join ' '))" "WARN"
            try { $process.Kill() } catch { }
            return $result
        }

        $result.ExitCode = $process.ExitCode
        $result.Output = $stdOutTask.Result
        $result.Error = $stdErrTask.Result
        $result.Success = ($process.ExitCode -eq 0)

        if (-not $result.Success) {
            Write-AppLog "Invoke-DockerCommand: exit code $($result.ExitCode) (docker $($Arguments -join ' '))" "WARN"
        }
        return $result
    } catch {
        $result.Error = $_.Exception.Message
        Write-AppLog "Invoke-DockerCommand: error running docker: $($_.Exception.Message)" "ERROR"
        return $result
    } finally {
        if ($process) { $process.Dispose() }
    }
}

# Canonical image name (must match docker/docker-compose.yml).
$script:AiDockerImageName = 'ai-docker-cli'
$script:AiDockerLegacyImageNames = @('docker-files-ai', 'ai-docker-ai', 'docker-ai')

function Test-ContainerVersionSkew {
    param(
        [Parameter(Mandatory)]
        [string]$LauncherVersion,

        # Newest release that actually changed container-side files (docker/).
        # When provided, skew is measured against this instead of the launcher
        # version, so launcher-only releases stop recommending a rebuild that
        # would change nothing inside the container.
        [string]$ContainerBaselineVersion = $null,

        [string]$DockerPath = $null,
        [string]$ContainerName = 'ai-cli'
    )

    $result = @{
        SkewDetected = $false
        LauncherVersion = $LauncherVersion
        ContainerVersion = $null
        LegacyImage = $false
        Error = $null
    }

    $launcherParsed = $null
    if (-not [Version]::TryParse($LauncherVersion, [ref]$launcherParsed)) {
        $result.Error = "Invalid launcher version: $LauncherVersion"
        return $result
    }

    $referenceParsed = $launcherParsed
    if ($ContainerBaselineVersion) {
        $baselineParsed = $null
        if ([Version]::TryParse($ContainerBaselineVersion, [ref]$baselineParsed)) {
            $referenceParsed = $baselineParsed
        } else {
            Write-AppLog "Invalid container baseline version '$ContainerBaselineVersion' - comparing against the launcher version instead." "WARN"
        }
    }

    $inspect = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
        'inspect', '--format', '{{index .Config.Labels "ai-docker.version"}}', $ContainerName
    ) -TimeoutSeconds 15
    if (-not $inspect.Success) {
        $result.Error = $inspect.Error
        return $result
    }

    $containerVersion = $inspect.Output.Trim()
    if (-not $containerVersion -or $containerVersion -eq '<no value>' -or $containerVersion -eq '0.0.0') {
        $result.LegacyImage = $true
        $result.SkewDetected = $true
        return $result
    }

    $containerParsed = $null
    if (-not [Version]::TryParse($containerVersion, [ref]$containerParsed)) {
        $result.Error = "Invalid container version: $containerVersion"
        $result.SkewDetected = $true
        return $result
    }

    $result.ContainerVersion = $containerVersion
    $result.SkewDetected = ($containerParsed -lt $referenceParsed)
    if ($result.SkewDetected) {
        Write-AppLog "Container version $containerVersion predates the newest container-side release ($referenceParsed)." "WARN"
    }
    return $result
}

function Test-ContainerImageSkew {
    param(
        [string]$DockerPath = $null,
        [string]$ContainerName = 'ai-cli',
        [string]$ImageName = $script:AiDockerImageName
    )

    $result = @{ SkewDetected = $false; ContainerImageId = $null; CurrentImageId = $null }
    if (-not $DockerPath) { $DockerPath = Find-Docker }
    if (-not $DockerPath) { return $result }

    $container = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
        'inspect', '--format', '{{.Image}}', $ContainerName
    ) -TimeoutSeconds 15
    if (-not $container.Success) { return $result }
    $result.ContainerImageId = $container.Output.Trim()

    $image = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
        'images', '--no-trunc', '-q', "${ImageName}:latest"
    ) -TimeoutSeconds 15
    if (-not $image.Success) { return $result }
    $result.CurrentImageId = (($image.Output -split "`r?`n") | Select-Object -First 1).Trim()

    if ($result.ContainerImageId -and $result.CurrentImageId -and
        $result.ContainerImageId -ne $result.CurrentImageId) {
        $result.SkewDetected = $true
        Write-AppLog "Container/image skew detected; recreate '$ContainerName' to use the current image." "WARN"
    }

    return $result
}

function DockerOk() {
    param(
        [int]$TimeoutSeconds = 30
    )
    Write-AppLog "Checking if Docker is running..." "DEBUG"
    try {
        $dockerPath = Find-Docker
        if (-not $dockerPath) {
            Write-AppLog "Docker executable not found - Docker is not running" "WARN"
            return $false
        }
        $p = Start-Process -FilePath $dockerPath -ArgumentList "info" -WindowStyle Hidden -PassThru
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            Write-AppLog "Docker info did not respond within ${TimeoutSeconds}s - treating as not running" "WARN"
            try { $p.Kill() } catch { }
            return $false
        }
        if ($p.ExitCode -eq 0) {
            Write-AppLog "Docker is running and responding" "DEBUG"
            return $true
        } else {
            Write-AppLog "Docker executable found but not running (exit code: $($p.ExitCode))" "WARN"
            return $false
        }
    } catch {
        Write-AppLog "Error checking Docker status: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Poll until a container reports a running (and, if health-checked, healthy)
# state. Returns $true when ready, $false on timeout or error.
function Wait-ContainerReady {
    param(
        [string]$ContainerName = 'ai-cli',

        [int]$TimeoutSeconds = 60,

        [int]$PollIntervalSeconds = 2,

        [int]$PollIntervalMs = 0,

        [string]$DockerPath = $null,

        # Also accept a running container whose tool install is only partial
        # (ready marker INSTALL_STATUS=partial; healthcheck unhealthy/starting).
        # The working tools are usable; $script:ContainerReadyState says which.
        [switch]$AllowDegraded
    )

    Write-AppLog "Waiting for container '$ContainerName' to be ready (timeout: ${TimeoutSeconds}s)..." "DEBUG"
    $script:ContainerReadyState = 'NotReady'
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $inspect = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
            'inspect', '--format',
            '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}',
            $ContainerName
        ) -TimeoutSeconds 15

        if ($inspect.Success) {
            $parts = $inspect.Output.Trim() -split '\|'
            $status = $parts[0]
            $health = if ($parts.Count -gt 1) { $parts[1] } else { 'none' }

            if ($status -eq 'running' -and ($health -eq 'none' -or $health -eq 'healthy')) {
                Write-AppLog "Container '$ContainerName' is ready (status: $status, health: $health)" "DEBUG"
                $script:ContainerReadyState = 'Healthy'
                return $true
            }
            if ($AllowDegraded -and $status -eq 'running' -and ($health -eq 'unhealthy' -or $health -eq 'starting')) {
                $marker = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
                    'exec', $ContainerName, 'cat', '/run/ai-docker-ready') -TimeoutSeconds 15
                if ($marker.Success -and $marker.Output -match '(?m)^ENTRYPOINT=ok\r?$' -and $marker.Output -match '(?m)^INSTALL_STATUS=partial\r?$') {
                    Write-AppLog "Container '$ContainerName' is running DEGRADED: some CLI tools failed to install (see 'ai-docker status')" "WARN"
                    $script:ContainerReadyState = 'Degraded'
                    return $true
                }
            }
            if ($status -in @('exited', 'dead')) {
                Write-AppLog "Container '$ContainerName' is in terminal state '$status' - not waiting further" "WARN"
                return $false
            }
            Write-AppLog "Container '$ContainerName' not ready yet (status: $status, health: $health)" "DEBUG"
        } else {
            Write-AppLog "Container '$ContainerName' not inspectable yet: $($inspect.Error)" "DEBUG"
        }

        if ($PollIntervalMs -gt 0) {
            Start-Sleep -Milliseconds $PollIntervalMs
        } else {
            Start-Sleep -Seconds $PollIntervalSeconds
        }
    }

    Write-AppLog "Timed out after ${TimeoutSeconds}s waiting for container '$ContainerName'" "WARN"
    return $false
}


# ---------------------------------------------------------------------------
# Rebuild / uninstall safety
# ---------------------------------------------------------------------------
# A recreate, rebuild or uninstall deletes the container's writable layer
# (/tmp and the home folder outside the named volumes). These helpers predict
# when that is about to happen and run the in-container rescue scanner first.

function Test-ContainerRecreateLikely {
    param(
        [string]$DockerPath = $null,
        [string]$ContainerName = 'ai-cli',
        [string]$ImageName = $script:AiDockerImageName,
        # Absolute compose files and project directory exactly as the coming
        # `compose up -d` will use them (so the same .env is read).
        [string[]]$ComposeFiles = @(),
        [string]$ProjectDirectory = $null,
        [string]$ServiceName = 'ai'
    )

    $result = @{ ContainerExists = $false; Likely = $false; Reason = '' }

    $containerImage = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
        'inspect', '--format', '{{.Image}}', $ContainerName) -TimeoutSeconds 15
    if (-not $containerImage.Success) {
        if (Test-DockerNotFound $containerImage) { return $result }
        # Timed out or failed: the container may well exist. Assume it does
        # and that it may be recreated, so the rescue check still runs.
        $result.ContainerExists = $true
        $result.Likely = $true
        $result.Reason = 'the container could not be inspected'
        return $result
    }
    $result.ContainerExists = $true

    $image = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
        'image', 'inspect', '--format', '{{.Id}}', $ImageName) -TimeoutSeconds 15
    if (-not $image.Success) {
        $result.Likely = $true
        $result.Reason = 'the image could not be inspected'
        return $result
    }
    if ($image.Output.Trim() -ne $containerImage.Output.Trim()) {
        $result.Likely = $true
        $result.Reason = 'the container image has changed'
        return $result
    }

    # Compose recreates the container when its service configuration changes
    # (ports, mounts, environment, resource limits, ...). It records a hash of
    # that configuration on the container; compare it with what compose would
    # generate now. Anything we cannot compare counts as a likely recreate.
    if (-not $ComposeFiles -or $ComposeFiles.Count -eq 0 -or -not $ProjectDirectory) {
        $result.Likely = $true
        $result.Reason = 'the configuration could not be compared'
        return $result
    }
    $label = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
        'inspect', '--format', '{{index .Config.Labels "com.docker.compose.config-hash"}}', $ContainerName) -TimeoutSeconds 15
    $hashArgs = @('compose', '--project-directory', $ProjectDirectory)
    foreach ($file in $ComposeFiles) { $hashArgs += @('-f', $file) }
    $hashArgs += @('config', '--hash', $ServiceName)
    $expected = Invoke-DockerCommand -DockerPath $DockerPath -Arguments $hashArgs -TimeoutSeconds 30
    $expectedHash = ''
    if ($expected.Success -and $expected.Output.Trim()) {
        $expectedHash = (($expected.Output.Trim() -split '\s+') | Select-Object -Last 1)
    }
    $currentHash = $label.Output.Trim()
    if (-not $label.Success -or -not $expectedHash -or -not $currentHash -or $currentHash -eq '<no value>') {
        $result.Likely = $true
        $result.Reason = 'the configuration could not be compared'
    } elseif ($expectedHash -ne $currentHash) {
        $result.Likely = $true
        $result.Reason = 'the container configuration has changed'
    }
    return $result
}

# Test-DockerNotFound <result>: docker said the object does not exist (as
# opposed to a timeout or any other failure, which proves nothing).
function Test-DockerNotFound($DockerResult) {
    if ($DockerResult.TimedOut) { return $false }
    return (("$($DockerResult.Error)`n$($DockerResult.Output)") -match 'No such (object|container)')
}

# Get-RescueDecision: what a caller about to remove or recreate the container
# may do with a rescue-scan state. Only an explicit Clean or a confirmed
# NoContainer allows proceeding; WorkFound offers the copy; every other state
# (Failed, Error, unknown) stops unless the user deliberately overrides.
function Get-RescueDecision {
    param([string]$State, [switch]$SkipRescueCheck)
    switch ($State) {
        'Clean'       { return 'Proceed' }
        'NoContainer' { return 'Proceed' }
        'WorkFound'   { return 'OfferCopy' }
    }
    if ($SkipRescueCheck) { return 'Proceed' }
    return 'Stop'
}

# Runs `ai-docker rescue-scan` inside the container using the launcher's own
# copy of the scanner, so containers built before it existed are covered too.
# State: NoContainer | Clean | WorkFound | Copied | Failed | Error
function Invoke-ContainerRescueScan {
    param(
        [Parameter(Mandatory)]
        [string]$ScannerDir,

        [switch]$Copy,

        [string]$DockerPath = $null,
        [string]$ContainerName = 'ai-cli'
    )

    $result = @{ State = 'Error'; Output = ''; Error = '' }
    $scanner = Join-Path $ScannerDir 'ai_docker.sh'
    $helpers = Join-Path (Join-Path $ScannerDir 'lib') 'entrypoint_helpers.sh'
    if (-not (Test-Path $scanner) -or -not (Test-Path $helpers)) {
        $result.Error = "Rescue scanner not found in $ScannerDir"
        return $result
    }

    $running = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
        'inspect', '--format', '{{.State.Running}}', $ContainerName) -TimeoutSeconds 15
    if (-not $running.Success) {
        # Only a confirmed "no such container" means there is nothing to lose.
        if (Test-DockerNotFound $running) {
            $result.State = 'NoContainer'
        } else {
            $result.Error = "Could not inspect the container: $($running.Error)"
        }
        return $result
    }
    if ($running.Output.Trim() -ne 'true') {
        $start = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @('start', $ContainerName) -TimeoutSeconds 60
        if (-not $start.Success) {
            $result.Error = "Could not start the container to check it: $($start.Error)"
            return $result
        }
    }

    $remoteDir = '/tmp/ai-docker-rescue'
    $steps = @(
        @('exec', '-u', 'root', $ContainerName, 'mkdir', '-p', $remoteDir),
        @('cp', $scanner, "${ContainerName}:$remoteDir/ai_docker.sh"),
        @('cp', $helpers, "${ContainerName}:$remoteDir/entrypoint_helpers.sh"),
        # Windows copies may carry CRLF; make the scripts readable by the user.
        @('exec', '-u', 'root', $ContainerName, 'sh', '-c', "sed -i 's/\r`$//' $remoteDir/*.sh && chmod 755 $remoteDir && chmod 644 $remoteDir/*.sh")
    )
    foreach ($step in $steps) {
        $r = Invoke-DockerCommand -DockerPath $DockerPath -Arguments $step -TimeoutSeconds 60
        if (-not $r.Success) {
            $result.Error = "Could not prepare the rescue scan: $($r.Error)"
            return $result
        }
    }

    $user = (Invoke-DockerCommand -DockerPath $DockerPath -Arguments @(
        'exec', $ContainerName, 'printenv', 'USER_NAME') -TimeoutSeconds 15).Output.Trim()
    if (-not $user) {
        $result.Error = 'Could not determine the container user'
        return $result
    }

    # Run as the user: git refuses to inspect repos owned by someone else.
    $scanArgs = @('exec', '-u', $user, '-w', '/tmp',
        '-e', "HOME=/home/$user", '-e', "AI_DOCKER_LIB_DIR=$remoteDir",
        $ContainerName, 'bash', "$remoteDir/ai_docker.sh", 'rescue-scan')
    if ($Copy) { $scanArgs += '--copy' }
    $scan = Invoke-DockerCommand -DockerPath $DockerPath -Arguments $scanArgs -TimeoutSeconds 900
    $result.Output = (($scan.Output, $scan.Error) | Where-Object { $_ }) -join "`n"

    switch ($scan.ExitCode) {
        0 { if ($Copy) { $result.State = 'Copied' } else { $result.State = 'Clean' } }
        3 { $result.State = 'WorkFound' }
        1 { $result.State = 'Failed' }
        4 {
            $result.State = 'Error'
            $result.Error = "The scan is incomplete: $($result.Output)"
        }
        default {
            $result.State = 'Error'
            $result.Error = "Rescue scan did not complete (exit $($scan.ExitCode)): $($scan.Error)"
        }
    }
    Write-AppLog "Rescue scan finished: $($result.State)" "INFO"
    return $result
}
