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
            if ($_ -match '\s|"') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
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
    $result.SkewDetected = ($containerParsed -lt $launcherParsed)
    if ($result.SkewDetected) {
        Write-AppLog "Container version $containerVersion is older than launcher version $LauncherVersion." "WARN"
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

        [string]$DockerPath = $null
    )

    Write-AppLog "Waiting for container '$ContainerName' to be ready (timeout: ${TimeoutSeconds}s)..." "DEBUG"
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
                return $true
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
