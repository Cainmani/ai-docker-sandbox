# PowerShell 5.1/.NET Framework compatible; also loaded from embedded text.
function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW quoting; never involves cmd.exe or wt.exe.
    '"' + ([regex]::Replace($Value, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}
function Get-AgentContainer {
    param([string]$DockerPath)
    $process = New-AgentProcess $DockerPath @('inspect','ai-cli') -Capture
    try {
        $out = $process.StandardOutput.ReadToEndAsync()
        $err = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { $process.Kill(); throw 'Docker Desktop did not respond. Check Docker Desktop, WSL or your VPN.' }
        if ($process.ExitCode -ne 0) { throw 'Run First Time Setup to create the workspace.' }
        $raw = $out.Result
    } finally { $process.Dispose() }
    $item = @($raw | ConvertFrom-Json)[0]
    if ([string]$item.Config.Image -notmatch '^(ai-docker-cli|docker-files-ai|ai-docker-ai|docker-ai)(:|$)') { throw 'The ai-cli container uses an unexpected image. Run setup to select the managed workspace.' }
    $userEntry = @($item.Config.Env | Where-Object { $_ -cmatch '^USER_NAME=' })
    if ($userEntry.Count -ne 1) { throw 'The container user is unavailable. Run setup again.' }
    $userName = $userEntry[0].Substring(10)
    if ($userName -notmatch '^[a-z_][a-z0-9_-]{0,31}$') { throw 'The container user is invalid.' }
    $mount = @($item.Mounts | Where-Object { $_.Destination -ceq '/workspace' })
    if ($mount.Count -ne 1 -or $mount[0].Type -ne 'bind') { throw 'The workspace mount is unavailable.' }
    $version = [string]$item.Config.Labels.'ai-docker.version'
    $parsed = $null
    $supported = [Version]::TryParse($version, [ref]$parsed) -and $parsed -ge [Version]'1.7.0'
    @{ User = $userName; Source = $mount[0].Source; Version = $version; Supported = $supported; Running = [bool]$item.State.Running; Id = $item.Id }
}
function ConvertTo-AgentFolder {
    param([string]$Folder)
    if ([string]::IsNullOrEmpty($Folder)) { return '/workspace' }
    if ($Folder -match '[\x00-\x1f]' -or $Folder -match '(^|/)\.\.?(/|$)' -or ($Folder -cne '/workspace' -and -not $Folder.StartsWith('/workspace/', [StringComparison]::Ordinal))) {
        throw 'Choose a folder inside /workspace without parent traversal.'
    }
    return $Folder
}
function New-AgentProcess {
    param([string]$Executable, [string[]]$Arguments, [switch]$Capture)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = [bool]$Capture
    $info.RedirectStandardOutput = [bool]$Capture
    $info.RedirectStandardError = [bool]$Capture
    if ($Capture) { $info.StandardOutputEncoding = [Text.Encoding]::UTF8; $info.StandardErrorEncoding = [Text.Encoding]::UTF8 }
    [System.Diagnostics.Process]::Start($info)
}
function ConvertFrom-AgentProtocol {
    param([string]$Text)
    $result = @{}
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^(PROTOCOL|ERROR|REPAIR_RESULT|CONTAINER_SUPPORTED|CONTAINER_VERSION|TOOL_(claude|codex|gh)|AUTH_(claude|codex|gh)|UPDATE_(RESULT|LAST_ATTEMPT|LAST_CHECK_OK|LAST_UPDATE_OK|FAILED_STAGES|SKIP_RESULT|SKIP_LAST_ATTEMPT))=([a-zA-Z0-9_ :.+-]{0,100})$') {
            $result[$Matches[1]] = $Matches[5]
        }
    }
    $result
}
function Start-AgentConsole {
    param([string]$ScriptPath, [string]$Action, [string]$Folder)
    $folderValue = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-AgentFolder $Folder)))
    # EncodedCommand also protects script paths with quotes/metacharacters. Values
    # become PowerShell single-quoted literals, not interpolated executable code.
    $command = '& ''' + $ScriptPath.Replace("'", "''") + "' -Action '" + $Action.Replace("'", "''") + "' -FolderBase64 '" + $folderValue + "'"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    New-AgentProcess powershell.exe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
}
