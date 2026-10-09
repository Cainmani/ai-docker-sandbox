# Explicit disposable pilot tooling. Never mounts production homes/credentials.
param(
    [ValidateSet('Start','Stop','Evidence')][string]$Action = 'Evidence',
    [string]$Workspace,
    [string]$PublicKey
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\agent_helpers.ps1"
$docker = (Get-Command docker -ErrorAction Stop).Source
$root = Split-Path -Parent $PSScriptRoot
$dockerDir = if (Test-Path (Join-Path $root 'docker\Dockerfile')) { Join-Path $root 'docker' } else { $PSScriptRoot }
$compose = Join-Path $dockerDir 'docker-compose.desktop-pilot.yml'
if ($Action -eq 'Evidence') {
    & $docker inspect --format 'Image={{.Image}} Running={{.State.Running}} Ports={{json .NetworkSettings.Ports}}' ai-desktop-pilot
    if ($LASTEXITCODE -ne 0) { throw 'Start the disposable pilot first.' }
    & $docker exec ai-desktop-pilot ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
    & $docker exec -u pilot ai-desktop-pilot bash -li -c 'printf "USER=%s\nHOME=%s\nPWD=%s\n" "$USER" "$HOME" "$PWD"; command -v claude; timeout 12 claude --version; for f in "$HOME/.claude/settings.json" "$HOME/.codex/config.toml"; do if [ -f "$f" ]; then sha256sum "$f"; fi; done'
    Write-Host 'Record before/after installation path, version, settings hashes, home and port binding privately. Never paste raw credentials or account identifiers into the PR.'
    exit
}
if (-not $Workspace -or -not $PublicKey) { throw 'Supply the same synthetic/public -Workspace and -PublicKey paths for Start/Stop.' }
$Workspace = [IO.Path]::GetFullPath($Workspace)
$PublicKey = (Resolve-Path -LiteralPath $PublicKey).Path
if ([IO.Path]::GetExtension($PublicKey) -ne '.pub') { throw 'Supply a public .pub key, never a private key.' }
if (-not (Test-Path -LiteralPath $Workspace)) { [void][IO.Directory]::CreateDirectory($Workspace) }
$state = Join-Path $env:LOCALAPPDATA 'AI-Docker-CLI\desktop-pilot'
[void][IO.Directory]::CreateDirectory($state)
$password = Join-Path $state 'password.txt'
if (-not (Test-Path -LiteralPath $password)) {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    [IO.File]::WriteAllText($password, [Convert]::ToBase64String($bytes))
}
$previous = @{}
foreach ($name in @('PILOT_WORKSPACE','PILOT_PUBLIC_KEY','PILOT_PASSWORD_FILE','AI_DOCKER_VERSION')) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$env:PILOT_WORKSPACE = $Workspace
$env:PILOT_PUBLIC_KEY = $PublicKey
$env:PILOT_PASSWORD_FILE = $password
$env:AI_DOCKER_VERSION = '1.7.0'
try {
    & $docker compose -f $compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Pilot configuration is invalid.' }
    if ($Action -eq 'Stop') {
        & $docker compose -f $compose stop
        if ($LASTEXITCODE -ne 0) { throw 'Pilot could not stop.' }
        Write-Host 'Pilot stopped. Workspace, private key and pilot state remain for review. Use the acceptance checklist for deliberate teardown.'
    } else {
        & $docker compose -f $compose up --build -d
        if ($LASTEXITCODE -ne 0) { throw 'Pilot could not start. Port 2222 may already be in use.' }
        $link = 'claude://code/new?ssh_host=' + [Uri]::EscapeDataString('pilot@127.0.0.1') + '&ssh_port=2222&ssh_folder=' + [Uri]::EscapeDataString('/workspace')
        $page = Join-Path $state 'project.html'
        [IO.File]::WriteAllText($page, '<!doctype html><meta charset="utf-8"><title>Disposable AI pilot</title><h1>Synthetic project</h1><p>Use public or synthetic material only. Verify the SSH host fingerprint first.</p><a href="' + [Net.WebUtility]::HtmlEncode($link) + '">Open in Claude Desktop</a><p>This starts a new session. Use Desktop to resume.</p>')
        Write-Host "Pilot is starting. After installation finishes, verify its fingerprint using -Action Evidence and SSH, then add the connection in Desktop. Link page: $page"
    }
} finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
}
