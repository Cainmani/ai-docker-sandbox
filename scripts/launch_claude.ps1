# Fixed-action console launcher; paths never pass through cmd.exe/wt.exe.
param(
    [ValidateSet('terminal','claude','codex','claude-login','codex-login','codex-device','claude-resume','codex-resume')]
    [string]$Action = 'terminal',
    [string]$FolderBase64 = 'L3dvcmtzcGFjZQ=='
)
. "$PSScriptRoot\log_utils.ps1"
. "$PSScriptRoot\docker_helpers.ps1"
. "$PSScriptRoot\agent_helpers.ps1"
try {
    $dockerPath = Find-Docker
    if (-not $dockerPath) { throw 'Install Docker Desktop, then run First Time Setup.' }
    $context = Get-AgentContainer $dockerPath
    if (-not $context.Running) {
        & $dockerPath start ai-cli | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Wait-ContainerReady -DockerPath $dockerPath -TimeoutSeconds 60 -AllowDegraded)) { throw 'Start Docker Desktop and wait for the workspace to finish starting.' }
        $context = Get-AgentContainer $dockerPath
    }
    $folder = ConvertTo-AgentFolder ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($FolderBase64)))
    $arguments = @('exec','-it','-u',$context.User,'ai-cli','bash','-li','-c')
    if ($context.Supported) {
        $arguments += @('exec /usr/local/bin/agent_session.sh "$1" "$2"','bash',$Action,$folder)
    } else {
        Write-Host 'This older container has no coordinated maintenance. Avoid repairs or updates while agents are running.'
        # Works with 1.6 startup files that cd /workspace. Reject symlink escapes.
        $command = 'p=$(realpath -e -- "$1" 2>/dev/null); if { [ "$p" != /workspace ] && [[ "$p" != /workspace/* ]]; } || ! cd -- "$1"; then echo "Selected folder is missing, inaccessible or outside the workspace. No agent started."; exec bash -i; fi; '
        $shellCommand = 'export AI_DOCKER_SESSION_FOLDER="$1"; exec bash --rcfile <(printf "%s\n" ''source "$HOME/.bashrc"'' ''cd -- "$AI_DOCKER_SESSION_FOLDER" || echo "Selected folder is no longer accessible."'' ''unset AI_DOCKER_SESSION_FOLDER'') -i'
        $command += switch ($Action) {
            'claude' { 'claude' }
            'codex' { 'codex' }
            'claude-login' { 'claude auth login' }
            'codex-login' { 'codex login' }
            'codex-device' { 'codex login --device-auth' }
            'claude-resume' { 'claude --resume' }
            'codex-resume' { 'codex resume' }
            default { $shellCommand }
        }
        $command += '; echo "Session finished. Terminal remains open."; ' + $shellCommand
        $arguments += @($command,'bash',$folder)
    }
    # Invoke the native executable directly in this console. PowerShell's native
    # argument marshalling on 5.1 is bypassed using the explicit Windows encoder.
    $process = New-AgentProcess $dockerPath $arguments
    try {
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } finally { $process.Dispose() }
    if ($exitCode -ne 0) {
        # docker exec returns the shell's last command status too. A nonzero
        # session exit alone does not mean Docker failed; recheck availability.
        try { $afterSession = Get-AgentContainer $dockerPath }
        catch { throw 'Unable to verify the workspace after the session. Check Docker Desktop and try again.' }
        if (-not $afterSession.Running) { throw 'The workspace stopped during the session. Start it again using the manager.' }
    }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to close this window')
}
