#Requires -Modules Pester

BeforeAll {
    . "$PSScriptRoot/../scripts/log_utils.ps1"
    . "$PSScriptRoot/../scripts/docker_helpers.ps1"
}

# These functions are Windows-only (use $env:ProgramFiles and -WindowStyle Hidden)
Describe 'Find-Docker' -Skip:(-not $IsWindows) {
    It 'Returns docker path when docker is in PATH' {
        Mock Get-Command { [PSCustomObject]@{ Source = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe' } }
        Find-Docker | Should -Be 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
    }

    It 'Returns null when docker is not found anywhere' {
        Mock Get-Command { $null }
        Mock Test-Path { $false }
        Find-Docker | Should -BeNullOrEmpty
    }

    It 'Falls back to ProgramFiles path when not in PATH' {
        Mock Get-Command { $null }
        Mock Test-Path { param($Path) $Path -eq "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe" }
        Find-Docker | Should -Be "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
    }

    It 'Checks multiple fallback paths' {
        Mock Get-Command { $null }
        Mock Test-Path { $false }
        Find-Docker | Should -BeNullOrEmpty
        Should -Invoke Test-Path -Times 3
    }
}

Describe 'DockerOk' -Skip:(-not $IsWindows) {
    It 'Returns true when Docker is running' {
        Mock Find-Docker { 'C:\Program Files\Docker\Docker\resources\bin\docker.exe' }
        Mock Start-Process {
            [PSCustomObject]@{ ExitCode = 0 } |
                Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true } -PassThru |
                Add-Member -MemberType ScriptMethod -Name Kill -Value { } -PassThru
        }
        DockerOk | Should -BeTrue
    }

    It 'Returns false when Find-Docker returns null' {
        Mock Find-Docker { $null }
        DockerOk | Should -BeFalse
    }

    It 'Returns false when docker info fails' {
        Mock Find-Docker { 'C:\docker.exe' }
        Mock Start-Process {
            [PSCustomObject]@{ ExitCode = 1 } |
                Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true } -PassThru |
                Add-Member -MemberType ScriptMethod -Name Kill -Value { } -PassThru
        }
        DockerOk | Should -BeFalse
    }

    It 'Returns false when docker info hangs past the timeout' {
        Mock Find-Docker { 'C:\docker.exe' }
        Mock Start-Process {
            [PSCustomObject]@{ ExitCode = $null } |
                Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $false } -PassThru |
                Add-Member -MemberType ScriptMethod -Name Kill -Value { } -PassThru
        }
        DockerOk -TimeoutSeconds 1 | Should -BeFalse
    }

    It 'Returns false and handles exception gracefully' {
        Mock Find-Docker { throw 'connection failed' }
        DockerOk | Should -BeFalse
    }
}

Describe 'Invoke-DockerCommand' {
    BeforeAll {
        # Cross-platform fake "docker" executables backed by real processes
        if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
            $script:FakeOk = Join-Path $TestDrive 'fake_ok.cmd'
            Set-Content -Path $script:FakeOk -Value "@echo off`r`necho fake-output`r`nexit /b 0" -Encoding ASCII
            $script:FakeFail = Join-Path $TestDrive 'fake_fail.cmd'
            Set-Content -Path $script:FakeFail -Value "@echo off`r`necho boom 1>&2`r`nexit /b 3" -Encoding ASCII
            $script:FakeSlow = Join-Path $TestDrive 'fake_slow.cmd'
            Set-Content -Path $script:FakeSlow -Value "@echo off`r`nping -n 30 127.0.0.1 > nul`r`nexit /b 0" -Encoding ASCII
        } else {
            $script:FakeOk = Join-Path $TestDrive 'fake_ok.sh'
            Set-Content -Path $script:FakeOk -Value "#!/bin/sh`necho fake-output`nexit 0"
            $script:FakeFail = Join-Path $TestDrive 'fake_fail.sh'
            Set-Content -Path $script:FakeFail -Value "#!/bin/sh`necho boom 1>&2`nexit 3"
            $script:FakeSlow = Join-Path $TestDrive 'fake_slow.sh'
            Set-Content -Path $script:FakeSlow -Value "#!/bin/sh`nsleep 30`nexit 0"
            chmod +x $script:FakeOk $script:FakeFail $script:FakeSlow
        }
    }

    It 'Returns error result when docker is not found' {
        Mock Find-Docker { $null }
        $result = Invoke-DockerCommand -Arguments @('info')
        $result.Success | Should -BeFalse
        $result.Error | Should -Match 'not found'
    }

    It 'Captures output and exit code 0 on success' {
        $result = Invoke-DockerCommand -Arguments @('info') -DockerPath $script:FakeOk
        $result.Success | Should -BeTrue
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'fake-output'
        $result.TimedOut | Should -BeFalse
    }

    It 'Captures stderr and nonzero exit code on failure' {
        $result = Invoke-DockerCommand -Arguments @('info') -DockerPath $script:FakeFail
        $result.Success | Should -BeFalse
        $result.ExitCode | Should -Be 3
        $result.Error | Should -Match 'boom'
    }

    It 'Times out and kills a hung command' {
        $result = Invoke-DockerCommand -Arguments @('info') -DockerPath $script:FakeSlow -TimeoutSeconds 1
        $result.Success | Should -BeFalse
        $result.TimedOut | Should -BeTrue
        $result.Error | Should -Match 'timed out'
    }

    It 'Returns error result for a nonexistent executable' {
        $result = Invoke-DockerCommand -Arguments @('info') -DockerPath (Join-Path $TestDrive 'no_such_docker')
        $result.Success | Should -BeFalse
        $result.Error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-ContainerVersionSkew' {
    It 'reports matching semantic versions as current' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "1.4.0`n"; Error = ''; TimedOut = $false } }
        $result = Test-ContainerVersionSkew -LauncherVersion '1.4.0' -DockerPath 'docker'
        $result.SkewDetected | Should -BeFalse
        $result.ContainerVersion | Should -Be '1.4.0'
    }

    It 'detects an older container version' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "1.3.5`n"; Error = ''; TimedOut = $false } }
        $result = Test-ContainerVersionSkew -LauncherVersion '1.4.0' -DockerPath 'docker'
        $result.SkewDetected | Should -BeTrue
    }

    It 'treats missing version metadata as a legacy image' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "<no value>`n"; Error = ''; TimedOut = $false } }
        $result = Test-ContainerVersionSkew -LauncherVersion '1.4.0' -DockerPath 'docker'
        $result.SkewDetected | Should -BeTrue
        $result.LegacyImage | Should -BeTrue
    }

    It 'surfaces Docker inspection errors without claiming skew' {
        Mock Invoke-DockerCommand { @{ Success = $false; ExitCode = 1; Output = ''; Error = 'daemon unavailable'; TimedOut = $false } }
        $result = Test-ContainerVersionSkew -LauncherVersion '1.4.0' -DockerPath 'docker'
        $result.SkewDetected | Should -BeFalse
        $result.Error | Should -Match 'daemon unavailable'
    }

    It 'does not report skew after a launcher-only release when the container meets the baseline' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "1.5.1`n"; Error = ''; TimedOut = $false } }
        $result = Test-ContainerVersionSkew -LauncherVersion '1.5.2' -ContainerBaselineVersion '1.5.0' -DockerPath 'docker'
        $result.SkewDetected | Should -BeFalse
        $result.ContainerVersion | Should -Be '1.5.1'
    }

    It 'reports skew when the container predates the baseline' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "1.4.3`n"; Error = ''; TimedOut = $false } }
        $result = Test-ContainerVersionSkew -LauncherVersion '1.5.2' -ContainerBaselineVersion '1.5.0' -DockerPath 'docker'
        $result.SkewDetected | Should -BeTrue
    }

    It 'falls back to the launcher version when the baseline is invalid' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "1.4.3`n"; Error = ''; TimedOut = $false } }
        $result = Test-ContainerVersionSkew -LauncherVersion '1.5.2' -ContainerBaselineVersion 'not-a-version' -DockerPath 'docker'
        $result.SkewDetected | Should -BeTrue
    }

    It 'still flags a legacy image when a baseline is provided' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "0.0.0`n"; Error = ''; TimedOut = $false } }
        $result = Test-ContainerVersionSkew -LauncherVersion '1.5.2' -ContainerBaselineVersion '1.5.0' -DockerPath 'docker'
        $result.SkewDetected | Should -BeTrue
        $result.LegacyImage | Should -BeTrue
    }
}

Describe 'Wait-ContainerReady' {
    BeforeEach {
        Mock Start-Sleep { }
    }

    It 'Returns true when container is running with no healthcheck' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "running|none`n"; Error = ''; TimedOut = $false } }
        Wait-ContainerReady -ContainerName 'ai-cli' -TimeoutSeconds 5 | Should -BeTrue
    }

    It 'Returns true when container is running and healthy' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "running|healthy`n"; Error = ''; TimedOut = $false } }
        Wait-ContainerReady -ContainerName 'ai-cli' -TimeoutSeconds 5 | Should -BeTrue
    }

    It 'Returns false immediately when container has exited' {
        Mock Invoke-DockerCommand { @{ Success = $true; ExitCode = 0; Output = "exited|none`n"; Error = ''; TimedOut = $false } }
        Wait-ContainerReady -ContainerName 'ai-cli' -TimeoutSeconds 5 | Should -BeFalse
        Should -Invoke Invoke-DockerCommand -Times 1 -Exactly
    }

    It 'Polls until the container becomes healthy' {
        $script:CallCount = 0
        Mock Invoke-DockerCommand {
            $script:CallCount++
            if ($script:CallCount -lt 3) {
                @{ Success = $true; ExitCode = 0; Output = "running|starting`n"; Error = ''; TimedOut = $false }
            } else {
                @{ Success = $true; ExitCode = 0; Output = "running|healthy`n"; Error = ''; TimedOut = $false }
            }
        }
        Wait-ContainerReady -ContainerName 'ai-cli' -TimeoutSeconds 30 | Should -BeTrue
        $script:CallCount | Should -Be 3
    }

    It 'Returns false on timeout' {
        Mock Invoke-DockerCommand { @{ Success = $false; ExitCode = 1; Output = ''; Error = 'No such container'; TimedOut = $false } }
        Wait-ContainerReady -ContainerName 'missing' -TimeoutSeconds 0 | Should -BeFalse
    }
}
