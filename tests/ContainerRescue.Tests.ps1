#Requires -Modules Pester

# Rebuild/uninstall safety: decide when a container recreate is imminent and
# run the rescue scanner inside the container before its writable layer is lost.

BeforeAll {
    . "$PSScriptRoot/../scripts/log_utils.ps1"
    . "$PSScriptRoot/../scripts/docker_helpers.ps1"

    function New-DockerResult([int]$ExitCode = 0, [string]$Output = '', [string]$ErrorText = '') {
        @{ Success = ($ExitCode -eq 0); ExitCode = $ExitCode; Output = $Output; Error = $ErrorText; TimedOut = $false }
    }
}

Describe 'Test-ContainerRecreateLikely' {
    BeforeEach {
        $script:composeFiles = @((Join-Path $TestDrive 'docker-compose.yml'))
        # Default world: same image, same compose config hash -> no recreate.
        $script:containerImage = 'sha256:same'
        $script:currentImage = 'sha256:same'
        $script:containerHash = 'abc123'
        $script:configHash = 'ai abc123'
        $script:hashExit = 0
        $script:imageExit = 0
        Mock Invoke-DockerCommand {
            $line = $Arguments -join ' '
            if ($line -like 'inspect --format {{.Image}}*') { return New-DockerResult 0 "$script:containerImage`n" }
            if ($line -like 'image inspect*') { return New-DockerResult $script:imageExit "$script:currentImage`n" }
            if ($line -like '*config-hash*') { return New-DockerResult 0 "$script:containerHash`n" }
            if ($line -like 'compose *config --hash*') { return New-DockerResult $script:hashExit "$script:configHash`n" }
            return New-DockerResult 0 ''
        }
    }

    It 'Reports no container when inspect fails' {
        Mock Invoke-DockerCommand { New-DockerResult 1 '' 'No such object' }
        $r = Test-ContainerRecreateLikely -DockerPath 'docker' -ComposeFiles $script:composeFiles -ProjectDirectory $TestDrive
        $r.ContainerExists | Should -BeFalse
        $r.Likely | Should -BeFalse
    }

    It 'Predicts no recreate when image and configuration are unchanged' {
        $r = Test-ContainerRecreateLikely -DockerPath 'docker' -ComposeFiles $script:composeFiles -ProjectDirectory $TestDrive
        $r.ContainerExists | Should -BeTrue
        $r.Likely | Should -BeFalse
    }

    It 'Predicts a recreate when the image changed' {
        $script:currentImage = 'sha256:new'
        $r = Test-ContainerRecreateLikely -DockerPath 'docker' -ComposeFiles $script:composeFiles -ProjectDirectory $TestDrive
        $r.Likely | Should -BeTrue
        $r.Reason | Should -Match 'image'
    }

    It 'Predicts a recreate for any configuration change (ports, workspace, limits)' {
        $script:configHash = 'ai def456'
        $r = Test-ContainerRecreateLikely -DockerPath 'docker' -ComposeFiles $script:composeFiles -ProjectDirectory $TestDrive
        $r.Likely | Should -BeTrue
        $r.Reason | Should -Match 'configuration'
    }

    It 'Treats an unreadable configuration hash as a likely recreate' {
        $script:hashExit = 1
        (Test-ContainerRecreateLikely -DockerPath 'docker' -ComposeFiles $script:composeFiles -ProjectDirectory $TestDrive).Likely | Should -BeTrue
    }

    It 'Treats a missing image as a likely recreate (cannot rule it out)' {
        $script:imageExit = 1
        (Test-ContainerRecreateLikely -DockerPath 'docker' -ComposeFiles $script:composeFiles -ProjectDirectory $TestDrive).Likely | Should -BeTrue
    }

    It 'Asks compose for the hash with absolute files and the project directory' {
        Test-ContainerRecreateLikely -DockerPath 'docker' -ComposeFiles $script:composeFiles -ProjectDirectory $TestDrive | Out-Null
        Should -Invoke Invoke-DockerCommand -ParameterFilter {
            ($Arguments -join ' ') -like "compose --project-directory $TestDrive -f $($script:composeFiles[0]) config --hash ai"
        }
    }
}

Describe 'Invoke-ContainerRescueScan' {
    BeforeEach {
        $script:dockerCalls = [System.Collections.Generic.List[string]]::new()
        $script:scanExit = 0
        $script:scanOutput = 'Nothing found outside the folders a rebuild keeps.'
        $script:running = 'true'
        $scannerDir = Join-Path $TestDrive 'docker-files'
        New-Item -ItemType Directory -Path (Join-Path $scannerDir 'lib') -Force | Out-Null
        Set-Content -Path (Join-Path $scannerDir 'ai_docker.sh') -Value '#!/bin/bash'
        Set-Content -Path (Join-Path $scannerDir 'lib/entrypoint_helpers.sh') -Value '#!/bin/bash'
        Mock Invoke-DockerCommand {
            $line = $Arguments -join ' '
            $script:dockerCalls.Add($line)
            if ($line -like 'inspect*State.Running*') { return New-DockerResult 0 "$script:running`n" }
            if ($line -like '*printenv USER_NAME*') { return New-DockerResult 0 "mike`n" }
            if ($line -like '*rescue-scan*') { return New-DockerResult $script:scanExit $script:scanOutput }
            return New-DockerResult 0 ''
        }
    }

    It 'Reports NoContainer when there is no container' {
        Mock Invoke-DockerCommand { New-DockerResult 1 '' 'No such container' }
        (Invoke-ContainerRescueScan -ScannerDir $scannerDir -DockerPath 'docker').State | Should -Be 'NoContainer'
    }

    It 'Copies the launcher''s own scanner into the container (old images lack it)' {
        Invoke-ContainerRescueScan -ScannerDir $scannerDir -DockerPath 'docker' | Out-Null
        ($script:dockerCalls | Where-Object { $_ -like 'cp *ai_docker.sh ai-cli:/tmp/ai-docker-rescue/*' }).Count | Should -Be 1
        ($script:dockerCalls | Where-Object { $_ -like 'cp *entrypoint_helpers.sh ai-cli:/tmp/ai-docker-rescue/*' }).Count | Should -Be 1
    }

    It 'Runs the scan as the container user with the copied library' {
        Invoke-ContainerRescueScan -ScannerDir $scannerDir -DockerPath 'docker' | Out-Null
        $scan = $script:dockerCalls | Where-Object { $_ -like '*rescue-scan*' }
        $scan | Should -Match '-u mike'
        $scan | Should -Match 'AI_DOCKER_LIB_DIR=/tmp/ai-docker-rescue'
        $scan | Should -Match 'HOME=/home/mike'
    }

    It 'Starts a stopped container before scanning' {
        $script:running = 'false'
        Invoke-ContainerRescueScan -ScannerDir $scannerDir -DockerPath 'docker' | Out-Null
        ($script:dockerCalls | Where-Object { $_ -eq 'start ai-cli' }).Count | Should -Be 1
    }

    It 'Maps exit 0 to Clean' {
        (Invoke-ContainerRescueScan -ScannerDir $scannerDir -DockerPath 'docker').State | Should -Be 'Clean'
    }

    It 'Maps exit 3 to WorkFound and returns the scanner output' {
        $script:scanExit = 3
        $script:scanOutput = "Found work outside the folders a rebuild keeps (1 location(s)):`n  folder /tmp/x"
        $r = Invoke-ContainerRescueScan -ScannerDir $scannerDir -DockerPath 'docker'
        $r.State | Should -Be 'WorkFound'
        $r.Output | Should -Match '/tmp/x'
    }

    It 'Passes --copy and maps success to Copied' {
        $r = Invoke-ContainerRescueScan -ScannerDir $scannerDir -DockerPath 'docker' -Copy
        ($script:dockerCalls | Where-Object { $_ -like '*rescue-scan --copy*' }).Count | Should -Be 1
        $r.State | Should -Be 'Copied'
    }

    It 'Maps a failed copy to Failed' {
        $script:scanExit = 1
        (Invoke-ContainerRescueScan -ScannerDir $scannerDir -DockerPath 'docker' -Copy).State | Should -Be 'Failed'
    }

    It 'Reports Error when the scanner files are missing' {
        $r = Invoke-ContainerRescueScan -ScannerDir (Join-Path $TestDrive 'nowhere') -DockerPath 'docker'
        $r.State | Should -Be 'Error'
    }
}

Describe 'Inspection failures are not "no container"' {
    It 'Rescue scan reports Error (not NoContainer) when docker inspect times out' {
        Mock Invoke-DockerCommand { @{ Success = $false; ExitCode = -1; Output = ''; Error = 'docker command timed out after 15s'; TimedOut = $true } }
        $dir = Join-Path $TestDrive 'df'; New-Item -ItemType Directory -Path (Join-Path $dir 'lib') -Force | Out-Null
        Set-Content (Join-Path $dir 'ai_docker.sh') 'x'; Set-Content (Join-Path $dir 'lib/entrypoint_helpers.sh') 'x'
        (Invoke-ContainerRescueScan -ScannerDir $dir -DockerPath 'docker').State | Should -Be 'Error'
    }

    It 'Rescue scan reports NoContainer only when Docker says the container does not exist' {
        Mock Invoke-DockerCommand { @{ Success = $false; ExitCode = 1; Output = ''; Error = 'Error: No such object: ai-cli'; TimedOut = $false } }
        $dir = Join-Path $TestDrive 'df2'; New-Item -ItemType Directory -Path (Join-Path $dir 'lib') -Force | Out-Null
        Set-Content (Join-Path $dir 'ai_docker.sh') 'x'; Set-Content (Join-Path $dir 'lib/entrypoint_helpers.sh') 'x'
        (Invoke-ContainerRescueScan -ScannerDir $dir -DockerPath 'docker').State | Should -Be 'NoContainer'
    }

    It 'Recreate prediction treats an inspect timeout as a possible recreate of an existing container' {
        Mock Invoke-DockerCommand { @{ Success = $false; ExitCode = -1; Output = ''; Error = 'docker command timed out after 15s'; TimedOut = $true } }
        $r = Test-ContainerRecreateLikely -DockerPath 'docker' -ComposeFiles @('x') -ProjectDirectory $TestDrive
        $r.ContainerExists | Should -BeTrue
        $r.Likely | Should -BeTrue
    }

    It 'Maps scanner exit 4 (incomplete scan) to Error' {
        Mock Invoke-DockerCommand {
            $line = $Arguments -join ' '
            if ($line -like 'inspect*State.Running*') { return @{ Success = $true; ExitCode = 0; Output = "true`n"; Error = ''; TimedOut = $false } }
            if ($line -like '*printenv USER_NAME*') { return @{ Success = $true; ExitCode = 0; Output = "mike`n"; Error = ''; TimedOut = $false } }
            if ($line -like '*rescue-scan*') { return @{ Success = $false; ExitCode = 4; Output = 'could not be read: /tmp/x'; Error = ''; TimedOut = $false } }
            return @{ Success = $true; ExitCode = 0; Output = ''; Error = ''; TimedOut = $false }
        }
        $dir = Join-Path $TestDrive 'df3'; New-Item -ItemType Directory -Path (Join-Path $dir 'lib') -Force | Out-Null
        Set-Content (Join-Path $dir 'ai_docker.sh') 'x'; Set-Content (Join-Path $dir 'lib/entrypoint_helpers.sh') 'x'
        $r = Invoke-ContainerRescueScan -ScannerDir $dir -DockerPath 'docker'
        $r.State | Should -Be 'Error'
        $r.Error | Should -Match 'could not be read'
    }
}

Describe 'Get-RescueDecision' {
    It 'Proceeds only on Clean or NoContainer' {
        Get-RescueDecision -State 'Clean' | Should -Be 'Proceed'
        Get-RescueDecision -State 'NoContainer' | Should -Be 'Proceed'
    }
    It 'Offers a copy when work was found' {
        Get-RescueDecision -State 'WorkFound' | Should -Be 'OfferCopy'
    }
    It 'Stops on every other state, including Failed, Error and anything unknown' {
        foreach ($state in @('Failed', 'Error', 'Copied', '', 'Surprise')) {
            Get-RescueDecision -State $state | Should -Be 'Stop'
        }
    }
    It 'Proceeds past a failed check only with an explicit override' {
        Get-RescueDecision -State 'Error' -SkipRescueCheck | Should -Be 'Proceed'
        Get-RescueDecision -State 'Failed' -SkipRescueCheck | Should -Be 'Proceed'
    }
    It 'Uninstall and the wizard both use it' {
        (Get-Content "$PSScriptRoot/../scripts/uninstall.ps1" -Raw) | Should -Match 'Get-RescueDecision'
        (Get-Content "$PSScriptRoot/../scripts/setup_wizard.ps1" -Raw) | Should -Match 'Get-RescueDecision'
    }
}

Describe 'Rebuild and uninstall paths run the rescue scan' {
    It 'Every container removal in the setup wizard goes through the rescue gate' {
        $wizard = Get-Content "$PSScriptRoot/../scripts/setup_wizard.ps1" -Raw
        $removals = [regex]::Matches($wizard, 'rm ai-cli')
        $removals.Count | Should -BeGreaterThan 0
        foreach ($m in $removals) {
            $before = $wizard.Substring([Math]::Max(0, $m.Index - 1500), [Math]::Min(1500, $m.Index))
            $before | Should -Match 'Invoke-RebuildRescueGate'
        }
    }

    It 'The setup wizard checks before starting (possibly recreating) the container' {
        $wizard = Get-Content "$PSScriptRoot/../scripts/setup_wizard.ps1" -Raw
        $scanIndex = $wizard.IndexOf('Invoke-RebuildRescueGate')
        $upIndex = $wizard.IndexOf('"$composeArgs up -d"')
        $scanIndex | Should -BeGreaterThan -1
        $scanIndex | Should -BeLessThan $upIndex
    }

    It 'Uninstall checks before removing the container' {
        $uninstall = Get-Content "$PSScriptRoot/../scripts/uninstall.ps1" -Raw
        $scanIndex = $uninstall.IndexOf('Invoke-ContainerRescueScan')
        $rmIndex = $uninstall.IndexOf('rm ai-cli')
        $scanIndex | Should -BeGreaterThan -1
        $scanIndex | Should -BeLessThan $rmIndex
    }

    It 'Uninstall -Force stops when the rescue check fails, unless explicitly skipped' {
        $uninstall = Get-Content "$PSScriptRoot/../scripts/uninstall.ps1" -Raw
        $uninstall | Should -Match '\[switch\]\$SkipRescueCheck'
        $uninstall | Should -Match 'Get-RescueDecision -State \$scan.State -SkipRescueCheck:\$SkipRescueCheck'
        $stopBranch = $uninstall.Substring($uninstall.IndexOf("`$decision -eq 'Stop'"))
        $stopBranch = $stopBranch.Substring(0, $stopBranch.IndexOf('}'))
        $stopBranch | Should -Not -Match '\$Force'
        $uninstall.Substring($uninstall.IndexOf("`$decision -eq 'Stop'")) | Should -Match 'exit 1'
    }

    It 'Uninstall stops when the rescue check itself is unavailable' {
        $uninstall = Get-Content "$PSScriptRoot/../scripts/uninstall.ps1" -Raw
        $block = $uninstall.Substring($uninstall.IndexOf('Get-Command Get-RescueDecision'))
        $block = $block.Substring(0, $block.IndexOf('} else {', $block.IndexOf('exit 1')))
        $block | Should -Match 'exit 1'
    }

    It 'The helpers uninstall needs are extracted next to it' {
        $complete = Get-Content "$PSScriptRoot/../scripts/AI_Docker_Complete.ps1" -Raw
        $complete | Should -Match "\`$dockerFiles = @\([^)]*'docker_helpers\.ps1'"
        $complete | Should -Match "\`$dockerFiles = @\([^)]*'log_utils\.ps1'"
    }
}
