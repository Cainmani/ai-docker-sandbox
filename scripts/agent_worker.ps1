# Background worker emits only whitelisted state. No vendor output is forwarded.
param([ValidateSet('health','repair')][string]$Operation='health', [ValidateSet('claude','codex')][string]$Tool='claude', [ValidateSet('ready','error','busy')][string]$SmokeScenario)
if ($SmokeScenario) {
    switch ($SmokeScenario) {
        'ready' { Write-Output "TOOL_claude=ready`nAUTH_claude=ready`nCONTAINER_SUPPORTED=1`nCONTAINER_VERSION=1.7.0" }
        'error' { Write-Output 'ERROR=workspace-stopped'; exit 1 }
        'busy' { Write-Output 'REPAIR_RESULT=75' }
    }
    exit 0
}
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\log_utils.ps1"
. "$PSScriptRoot\docker_helpers.ps1"
. "$PSScriptRoot\agent_helpers.ps1"
try {
    $docker = Find-Docker
    if (-not $docker) { Write-Output 'ERROR=docker-missing'; exit 1 }
    $context = Get-AgentContainer $docker
    if (-not $context.Running) { Write-Output 'ERROR=workspace-stopped'; exit 1 }
    if ($Operation -eq 'repair' -and -not $context.Supported) { Write-Output 'ERROR=container-old'; exit 69 }
    $base = @('exec','-u',$context.User,'ai-cli','bash','-li','-c')
    if ($Operation -eq 'repair') {
        $id = [Guid]::NewGuid().ToString('N')
        # Detached container command owns maintenance. Closing the window/worker
        # cannot interrupt package replacement. Only the exit code is persisted.
        $command = 'mkdir -p "$HOME/.ai-docker"; find "$HOME/.ai-docker" -maxdepth 1 -type f -regextype posix-extended -regex ".*/repair-[0-9a-f]{32}" -mtime +7 -delete; /usr/local/bin/install_cli_tools.sh --repair-tool "$1" >/dev/null 2>&1; rc=$?; mkdir -p "$HOME/.ai-docker"; f="$HOME/.ai-docker/repair-$2"; printf "%s\n" "$rc" > "$f.tmp"; mv -f -- "$f.tmp" "$f"'
        $started = Invoke-DockerCommand -DockerPath $docker -Arguments (@('exec','-d','-u',$context.User,'ai-cli','bash','-li','-c') + @($command,'bash',$Tool,$id)) -TimeoutSeconds 15
        if (-not $started.Success) { Write-Output 'ERROR=repair-start-failed'; exit 1 }
        $deadline = [DateTime]::UtcNow.AddMinutes(20)
        $repairCode = -1
        while ([DateTime]::UtcNow -lt $deadline) {
            $poll = Invoke-DockerCommand -DockerPath $docker -Arguments (@('exec','-u',$context.User,'ai-cli','bash','-c') + @('f="$HOME/.ai-docker/repair-$1"; test -f "$f" && { cat -- "$f"; rm -f -- "$f"; }','bash',$id)) -TimeoutSeconds 15
            if ($poll.Success -and $poll.Output.Trim() -match '^[0-9]{1,3}$' -and [int]$poll.Output.Trim() -le 255) { $repairCode=[int]$poll.Output.Trim(); break }
            Start-Sleep -Seconds 1
        }
        if ($repairCode -lt 0) { Write-Output 'ERROR=repair-unverified'; exit 1 }
        Write-Output "REPAIR_RESULT=$repairCode"
    } else {
        $command = if ($context.Supported) { 'exec /usr/local/bin/agent_health.sh' } else { 'for t in claude codex; do if timeout 12 "$t" --version >/dev/null 2>&1; then echo "TOOL_$t=ready"; else echo "TOOL_$t=broken"; fi; done' }
        $probe = Invoke-DockerCommand -DockerPath $docker -Arguments ($base + @($command)) -TimeoutSeconds 80
        if (-not $probe.Success) { if ($probe.ExitCode -eq 75) { Write-Output 'ERROR=maintenance-busy' } else { Write-Output 'ERROR=health-unverified' }; exit 1 }
        $values = ConvertFrom-AgentProtocol $probe.Output
        foreach ($key in $values.Keys) { Write-Output "$key=$($values[$key])" }
    }
    $current = Get-AgentContainer $docker
    if ($current.Id -ne $context.Id) { Write-Output 'ERROR=workspace-recreated'; exit 1 }
    Write-Output ('CONTAINER_SUPPORTED=' + [int]$context.Supported)
    $version = if ($context.Version -match '^\d+\.\d+\.\d+$') { $context.Version } else { 'unknown' }
    Write-Output "CONTAINER_VERSION=$version"
} catch {
    Write-Output 'ERROR=workspace-unavailable'
    exit 1
}
