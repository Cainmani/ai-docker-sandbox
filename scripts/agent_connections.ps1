# Health and native sign-in screen, hosted outside the EXE. No vendor settings writes.
param([switch]$SmokeTest)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. "$PSScriptRoot\log_utils.ps1"
. "$PSScriptRoot\docker_helpers.ps1"
. "$PSScriptRoot\agent_helpers.ps1"
$script:Work = $null
$script:Generation = 0
$script:SmokePhase = 0
$script:SmokeExit = 0
$script:Support = 'AI Docker: health has not been checked.'
$screen = New-Object Windows.Forms.Form
$screen.Text = 'AI Docker - Ready to work'
$screen.ClientSize = New-Object Drawing.Size(640, 500)
$screen.StartPosition = 'CenterScreen'
$tool = New-Object Windows.Forms.ComboBox
$tool.SetBounds(20,20,180,30)
$tool.DropDownStyle = 'DropDownList'
[void]$tool.Items.Add('Claude')
$tool.SelectedIndex = 0
$advanced = New-Object Windows.Forms.CheckBox
$advanced.Text = 'Advanced (Codex)'
$advanced.SetBounds(220,20,200,30)
$advanced.Add_CheckedChanged({
    if ($advanced.Checked) { if ($tool.Items.Count -eq 1) { [void]$tool.Items.Add('Codex') } }
    else { $tool.SelectedIndex = 0; $tool.Items.Remove('Codex') }
    $script:Generation++
})
$folderLabel = New-Object Windows.Forms.Label
$folderLabel.Text = 'Folder inside the workspace (for example /workspace/my-project)'
$folderLabel.SetBounds(20,60,600,25)
$folder = New-Object Windows.Forms.TextBox
$folder.Text = '/workspace'
$folder.SetBounds(20,88,600,28)
$tool.Add_SelectedIndexChanged({ $script:Generation++ })
$status = New-Object Windows.Forms.TextBox
$status.Multiline = $true
$status.ReadOnly = $true
$status.ScrollBars = 'Vertical'
$status.SetBounds(20,130,600,180)
$status.Text = 'Check health to see whether Docker, tools and sign-in are ready.'
$screen.Controls.AddRange(@($tool,$advanced,$folderLabel,$folder,$status))
$buttons = @{}
foreach ($spec in @(@('Check health',20,330),@('Sign in',170,330),@('Open',320,330),@('Resume',470,330),@('Repair this tool',20,375),@('Open terminal',170,375),@('Copy support',320,375),@('Device sign-in',470,375))) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $spec[0]
    $button.SetBounds($spec[1],$spec[2],140,32)
    $screen.Controls.Add($button)
    $buttons[$spec[0]] = $button
}
$note = New-Object Windows.Forms.Label
$note.Text = 'Sign-in uses the vendor terminal. Ready means the tool starts and native login status succeeds; it does not verify network access, credits or company-data approval.'
$note.SetBounds(20,425,600,65)
$screen.Controls.Add($note)
function Set-AgentBusy([bool]$Busy) { foreach ($button in $buttons.Values) { $button.Enabled = -not $Busy } }
function Open-AgentAction([string]$Action) {
    try {
        $selected = ConvertTo-AgentFolder $folder.Text
        [void](Start-AgentConsole (Join-Path $PSScriptRoot 'launch_claude.ps1') $Action $selected)
        $status.Text = 'Terminal opened. Complete the vendor steps there, then check health again.'
    } catch { $status.Text = $_.Exception.Message }
}
function Begin-AgentHealth([switch]$Repair) {
    if ($script:Work) { return }
    try {
        $operation = if ($Repair) { 'repair' } else { 'health' }
        $workerArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'agent_worker.ps1'),'-Operation',$operation,'-Tool',$tool.Text.ToLowerInvariant())
        if ($SmokeTest) {
            $scenario = switch ($script:SmokePhase) { 1 { 'ready' } 2 { 'error' } 3 { 'busy' } }
            $workerArgs += @('-SmokeScenario',$scenario)
        }
        $process = New-AgentProcess powershell.exe $workerArgs -Capture
        $script:Work = @{ Process=$process; Out=$process.StandardOutput.ReadToEndAsync(); Err=$process.StandardError.ReadToEndAsync(); Generation=$script:Generation; Repair=[bool]$Repair; Started=[DateTime]::UtcNow }
        Set-AgentBusy $true
        $status.Text = if ($Repair) { 'Repair running. Working settings and other tools are preserved. You may close this window; container maintenance will continue.' } else { 'Checking health...' }
    } catch {
        $status.Text = $_.Exception.Message
        $script:Support = 'AI Docker: ' + $_.Exception.Message + ' Check Docker Desktop / WSL, VPN and proxy settings. No credentials are included.'
    }
}
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    if (-not $script:Work) { return }
    $work = $script:Work
    if (-not $work.Process.HasExited) {
        if (-not $work.Repair -and ([DateTime]::UtcNow - $work.Started).TotalSeconds -gt 100) { $work.Process.Kill(); $status.Text = 'Unable to verify: health check timed out. Check Docker Desktop, VPN or proxy.' }
        return
    }
    try {
        if ($work.Generation -ne $script:Generation) { $status.Text = 'Selection changed. Check health again.'; return }
        $values = ConvertFrom-AgentProtocol $work.Out.Result
        $errorCode = $values['ERROR']
        if ($errorCode) {
            $status.Text = switch ($errorCode) {
                'docker-missing' { 'Install Docker Desktop, then run First Time Setup.' }
                'maintenance-busy' { 'Maintenance is running. Check health again when it finishes.' }
                'workspace-stopped' { 'Start Docker Desktop and the ai-cli workspace, then check again.' }
                'container-old' { 'Repair requires setup/recreate with the 1.7 container. Existing tools remain available in the terminal.' }
                'workspace-recreated' { 'The workspace was recreated. Check health again.' }
                'repair-unverified' { 'Unable to verify repair completion. It may still be running. Check health before trying again.' }
                default { 'Unable to verify. Check Docker Desktop / WSL, VPN, proxy and CA settings, then try again.' }
            }
        } elseif ($work.Repair) {
            $status.Text = switch ($values['REPAIR_RESULT']) { '0' { 'Repair finished. Check health again.' } '75' { 'Tools are in use or maintenance is running. Close agent sessions and try again.' } '69' { 'Maintenance coordination unavailable. Recreate the container using setup.' } default { 'Repair failed. Saved settings remain available. Check network access and copy support details.' } }
        } elseif ($work.Process.ExitCode -ne 0) { $status.Text = 'Unable to verify. Check Docker Desktop, VPN or proxy and try again.' }
        else {
            $name = $tool.Text.ToLowerInvariant()
            $status.Text = if ($values['TOOL_'+$name] -ne 'ready') { 'Fix this: the selected tool could not start. Repair this tool, then check again.' } elseif ($values['AUTH_'+$name] -eq 'ready') { ('Ready. Open a session or resume a conversation. Checked locally at ' + [DateTime]::Now.ToShortTimeString() + '.') } else { 'Tool ready. Sign-in: unable to verify. Sign in using the native terminal, then check again.' }
            if ($values['UPDATE_SKIP_RESULT'] -eq 'skipped_busy') { $status.AppendText("`r`nUpdate skipped: busy at " + $values['UPDATE_SKIP_LAST_ATTEMPT']) }
            if ($values.ContainsKey('UPDATE_RESULT')) { $status.AppendText("`r`nLast update: " + $values['UPDATE_RESULT']) }
            if ($values['CONTAINER_SUPPORTED'] -ne '1') { $status.AppendText("`r`nOlder/unknown container: native terminal available; new diagnostics and repair require setup/recreate.") }
        }
        $script:Support = 'AI Docker: ' + $status.Text + ' Container version: ' + $values['CONTAINER_VERSION'] + '. Check Docker Desktop / WSL, VPN and proxy if connections fail. No credentials or folder paths included.'
    } catch { $status.Text = 'Unable to verify. The workspace may have stopped. Check Docker Desktop.' }
    finally {
        $work.Process.Dispose(); $script:Work=$null; Set-AgentBusy $false
        if ($SmokeTest) {
            $expected = switch ($script:SmokePhase) { 1 { '^Ready\.' } 2 { '^Start Docker Desktop' } 3 { '^Tools are in use' } }
            if ($status.Text -notmatch $expected) { $script:SmokeExit=1; $screen.Close() }
            elseif ($script:SmokePhase -eq 3) { $screen.Close() }
            else { $script:SmokePhase++; if ($script:SmokePhase -eq 3) { Begin-AgentHealth -Repair } else { Begin-AgentHealth } }
        }
    }
})
$buttons['Check health'].Add_Click({ Begin-AgentHealth })
$buttons['Sign in'].Add_Click({ Open-AgentAction ($tool.Text.ToLowerInvariant()+'-login') })
$buttons['Open'].Add_Click({ Open-AgentAction $tool.Text.ToLowerInvariant() })
$buttons['Resume'].Add_Click({ Open-AgentAction ($tool.Text.ToLowerInvariant()+'-resume') })
$buttons['Open terminal'].Add_Click({ Open-AgentAction 'terminal' })
$buttons['Copy support'].Add_Click({
    if ([Windows.Forms.MessageBox]::Show($script:Support + "`r`n`r`nCopy this summary to the clipboard?", 'Support summary', 'YesNo', 'Information') -eq 'Yes') {
        [Windows.Forms.Clipboard]::SetText($script:Support)
    }
})
$buttons['Device sign-in'].Add_Click({
    if ($tool.Text -ne 'Codex') { $status.Text = 'Device sign-in is available for Codex. Choose it under Advanced.'; return }
    Open-AgentAction 'codex-device'
    $status.AppendText("`r`nEnable device-code login in ChatGPT security settings (or ask your workspace admin) before using this beta flow.")
})
$buttons['Repair this tool'].Add_Click({
    if ([Windows.Forms.MessageBox]::Show('Reinstall only the selected tool? Close agent sessions first. Saved sign-in and vendor settings are preserved.','Repair this tool','YesNo','Question') -eq 'Yes') { Begin-AgentHealth -Repair }
})
$screen.Add_FormClosed({ $timer.Stop(); $timer.Dispose(); if ($script:Work) { $script:Work.Process.Dispose() } })
$timer.Start()
if ($SmokeTest) {
    # Exercise real form creation, event wiring, and timer dispatch without Docker.
    $screen.Add_Shown({ $script:SmokePhase=1; Begin-AgentHealth })
}
[void]$screen.ShowDialog()

if ($SmokeTest) { exit $script:SmokeExit }
