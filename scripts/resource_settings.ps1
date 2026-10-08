# Resource planning, persistence and live Docker updates. Windows PowerShell 5.1 compatible.
# Dependencies: env_utils.ps1, wsl_config.ps1 and docker_helpers.ps1.
function Get-ContainerResourcePlan {
    param([string]$Profile, [double]$SystemRAMGB, [int]$SystemCores,
          [string]$WSLConfigPath, [string]$EnvPath)
    $config = Parse-WSLConfig -Path $WSLConfigPath
    if ((Test-Path -LiteralPath $WSLConfigPath) -and -not $config.Exists) { throw 'The existing WSL settings could not be read.' }
    $saved = @{}
    if ($EnvPath) { $saved = Read-EnvFile -Path $EnvPath }
    $custom = $false
    if ($Profile -in @('light', 'standard', 'heavy')) {
        $memory = ConvertTo-MemoryBytes (Get-ProfileMemory $Profile)
        $cpus = Resolve-ContainerCpuLimit -Profile $Profile -SystemCores $SystemCores
        $source = "$Profile profile"
    } else {
        if ($config.Memory) {
            $memory = ConvertTo-MemoryBytes $config.Memory
            $source = 'existing WSL settings'
        } elseif ($SystemRAMGB -gt 0) {
            # WSL's documented default is half the host RAM.
            $memory = [long][Math]::Floor($SystemRAMGB * 1GB / 2)
            $source = 'WSL default: half of host RAM'
        } else { throw 'Could not determine the WSL memory budget.' }
        $cpus = Resolve-ContainerCpuLimit -Profile 'keep' -SystemCores $SystemCores -ExistingProcessors $config.Processors
        if ($saved['AI_DOCKER_CUSTOM_RESOURCES'] -eq '1') {
            $requestedMemory = ConvertTo-MemoryBytes $saved['AI_DOCKER_MEMORY_LIMIT']
            $requestedCpu = 0
            if (-not [int]::TryParse($saved['AI_DOCKER_CPU_LIMIT'], [ref]$requestedCpu) -or $requestedCpu -lt 1) {
                throw 'The saved container CPU limit is invalid.'
            }
            if ($requestedMemory -gt $memory -or $requestedCpu -gt $cpus) {
                throw 'Saved container limits exceed the WSL settings. Adjust them with Resources in the launcher.'
            }
            $memory = $requestedMemory
            $cpus = $requestedCpu
            $custom = $true
            $source = 'saved custom settings'
        }
    }
    return @{ MemoryBytes = $memory; MemoryGB = ($memory / 1GB).ToString('0.##'); CpuCount = $cpus; Custom = $custom; Source = $source }
}

function Save-ContainerResourceSettings {
    param([string]$EnvPath, [long]$MemoryBytes, [int]$CpuCount, [bool]$Custom = $false)
    if ($MemoryBytes -lt 6MB -or $CpuCount -lt 1) { throw 'Invalid container resource limits.' }
    $lines = @()
    if (Test-Path -LiteralPath $EnvPath) { $lines = @(Get-Content -LiteralPath $EnvPath -Encoding UTF8 -ErrorAction Stop) }
    $lines = @($lines | Where-Object { $_ -notmatch '^\s*(AI_DOCKER_MEMORY_LIMIT|AI_DOCKER_CPU_LIMIT|AI_DOCKER_CUSTOM_RESOURCES)\s*=' })
    $lines += "AI_DOCKER_MEMORY_LIMIT=$MemoryBytes", "AI_DOCKER_CPU_LIMIT=$CpuCount", "AI_DOCKER_CUSTOM_RESOURCES=$([int]$Custom)"
    if (-not (Write-EnvFileAtomic -Path $EnvPath -Lines $lines)) { throw 'Could not save the container resource settings.' }
}

function Set-RunningContainerResources {
    param([string]$DockerPath, [string]$EnvPath, [long]$MemoryBytes, [int]$CpuCount,
          [long]$MaxMemoryBytes, [int]$MaxCpuCount, [string]$ContainerName = 'ai-cli')
    if ($MemoryBytes -lt 6MB -or $MemoryBytes -gt $MaxMemoryBytes -or $CpuCount -lt 1 -or $CpuCount -gt $MaxCpuCount) {
        throw 'Requested resources must fit within the current WSL/Docker limits.'
    }
    # Inspect before changing anything; failures must not invent default limits.
    $before = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @('inspect', '--format', '{{json .HostConfig}}', $ContainerName)
    if (-not $before.Success) { throw "Could not inspect the container: $($before.Error)" }
    $old = $before.Output | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $old.Memory -or $null -eq $old.NanoCpus -or $null -eq $old.MemorySwap) { throw 'Container resource settings are incomplete.' }
    # Preserve the amount of allowed swap while increasing/decreasing the RAM cap.
    $swap = [long]$old.MemorySwap
    if ($swap -gt 0) { $swap = $MemoryBytes + [Math]::Max([long]0, $swap - [long]$old.Memory) }
    elseif ($swap -eq 0) { $swap = 2 * $MemoryBytes }
    $updateArguments = @('update', '--memory', "$MemoryBytes", '--memory-swap', "$swap", '--cpus', "$CpuCount", $ContainerName)
    $oldCpu = ([double]$old.NanoCpus / 1e9).ToString('0.#########', [Globalization.CultureInfo]::InvariantCulture)
    $oldSwap = [long]$old.MemorySwap
    if ($oldSwap -eq 0 -and [long]$old.Memory -gt 0) { $oldSwap = 2 * [long]$old.Memory }
    $rollbackArgs = @('update', '--memory', "$($old.Memory)", '--memory-swap', "$oldSwap", '--cpus', $oldCpu, $ContainerName)
    try {
        $changed = Invoke-DockerCommand -DockerPath $DockerPath -Arguments $updateArguments
        if (-not $changed.Success) { throw "Docker could not apply the limits: $($changed.Error)" }
        $check = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @('inspect', '--format', '{{json .HostConfig}}', $ContainerName)
        if (-not $check.Success) { throw 'The new limits could not be verified.' }
        $actual = $check.Output | ConvertFrom-Json -ErrorAction Stop
        if ([long]$actual.Memory -ne $MemoryBytes -or [long]$actual.NanoCpus -ne $CpuCount * 1e9 -or [long]$actual.MemorySwap -ne $swap) {
            throw 'Docker did not report the requested limits.'
        }
        Save-ContainerResourceSettings -EnvPath $EnvPath -MemoryBytes $MemoryBytes -CpuCount $CpuCount -Custom $true
    } catch {
        $message = $_.Exception.Message
        # A timeout may still have applied the update. Attempt to restore the inspected limits.
        $rollback = Invoke-DockerCommand -DockerPath $DockerPath -Arguments $rollbackArgs
        if ($rollback.Success) {
            $restored = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @('inspect', '--format', '{{json .HostConfig}}', $ContainerName)
            if ($restored.Success) {
                try {
                    $restoredLimits = $restored.Output | ConvertFrom-Json -ErrorAction Stop
                    $verified = ([long]$restoredLimits.Memory -eq [long]$old.Memory -and [long]$restoredLimits.NanoCpus -eq [long]$old.NanoCpus -and [long]$restoredLimits.MemorySwap -eq $oldSwap)
                } catch { $verified = $false }
                if ($verified) { throw "$message Previous running limits restored; settings were not saved." }
            }
        }
        throw "$message Could not restore the previous running limits. Check docker stats before retrying."
    }
}

function Show-ContainerResourceDialog {
    param([string]$EnvPath, [string]$DockerPath, $Owner)
    if (-not (Test-Path -LiteralPath $EnvPath)) { throw 'Run setup before changing container resources.' }
    if (-not $DockerPath) { throw 'Docker Desktop could not be found.' }
    $inspect = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @('inspect', '--format', '{{json .HostConfig}}', 'ai-cli')
    $info = Invoke-DockerCommand -DockerPath $DockerPath -Arguments @('info', '--format', '{{json .}}')
    if (-not $inspect.Success -or -not $info.Success) { throw 'Start Docker Desktop and the AI container, then try Resources again.' }
    $current = $inspect.Output | ConvertFrom-Json -ErrorAction Stop
    $hostInfo = $info.Output | ConvertFrom-Json -ErrorAction Stop
    $plan = Get-ContainerResourcePlan -Profile 'keep' -SystemRAMGB (Get-SystemMemoryGB) -SystemCores (Get-ProcessorCount) `
        -WSLConfigPath "$env:USERPROFILE\.wslconfig" -EnvPath ''
    $maxMemory = [long][Math]::Min([long]$hostInfo.MemTotal, $plan.MemoryBytes)
    $maxCpu = [int][Math]::Min([int]$hostInfo.NCPU, $plan.CpuCount)
    if ($maxMemory -lt 1GB -or $maxCpu -lt 1) { throw 'Docker has too few resources for this settings dialog.' }
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'AI Docker Resources'
    $dialog.ClientSize = New-Object System.Drawing.Size(500, 290)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $description = New-Object System.Windows.Forms.Label
    $description.SetBounds(20, 15, 460, 95)
    $description.Text = "Change this container's limits without rebuilding or restarting it.`n`nWSL/Docker currently allows up to $([Math]::Round($maxMemory / 1GB, 2)) GB RAM and $maxCpu CPUs.`nVmmemWSL also includes other WSL processes and file cache."
    $dialog.Controls.Add($description)
    $ramLabel = New-Object System.Windows.Forms.Label
    $ramLabel.Text = 'RAM limit (GB)'; $ramLabel.SetBounds(20, 120, 160, 25)
    $cpuLabel = New-Object System.Windows.Forms.Label
    $cpuLabel.Text = 'CPU limit'; $cpuLabel.SetBounds(20, 160, 160, 25)
    $ram = New-Object System.Windows.Forms.NumericUpDown
    $ram.SetBounds(190, 120, 140, 25); $ram.Minimum = 1; $ram.DecimalPlaces = 2; $ram.Increment = 0.5
    $ram.Maximum = [decimal][Math]::Floor($maxMemory / 1GB * 100) / 100
    $ram.Value = [decimal][Math]::Max(1, [Math]::Min($ram.Maximum, [long]$current.Memory / 1GB))
    $cpu = New-Object System.Windows.Forms.NumericUpDown
    $cpu.SetBounds(190, 160, 140, 25); $cpu.Minimum = 1; $cpu.Maximum = $maxCpu
    $cpu.Value = [Math]::Max(1, [Math]::Min($maxCpu, [double]$current.NanoCpus / 1e9))
    foreach ($control in @($ramLabel, $cpuLabel, $ram, $cpu)) { $dialog.Controls.Add($control) }
    $note = New-Object System.Windows.Forms.Label
    $note.SetBounds(20, 195, 460, 35)
    $note.Text = 'Lower limits can stop busy tools. Save your work before applying.'
    $dialog.Controls.Add($note)
    $apply = New-Object System.Windows.Forms.Button
    $apply.Text = 'Apply and save'; $apply.SetBounds(190, 245, 140, 30)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.SetBounds(345, 245, 100, 30); $cancel.DialogResult = 'Cancel'
    $dialog.Controls.Add($apply); $dialog.Controls.Add($cancel); $dialog.CancelButton = $cancel
    $apply.Add_Click({
        $apply.Enabled = $false
        try {
            Set-RunningContainerResources -DockerPath $DockerPath -EnvPath $EnvPath -MemoryBytes ([long]($ram.Value * 1GB)) `
                -CpuCount ([int]$cpu.Value) -MaxMemoryBytes $maxMemory -MaxCpuCount $maxCpu
            [System.Windows.Forms.MessageBox]::Show('Limits applied and saved. No rebuild or restart was needed.', 'Resources', 'OK', 'Information') | Out-Null
            $dialog.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Resources', 'OK', 'Error') | Out-Null
        } finally { $apply.Enabled = $true }
    })
    try { $dialog.ShowDialog($Owner) | Out-Null } finally { $dialog.Dispose() }
}
