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
    It 'Reports no container when inspect fails' {
        Mock Invoke-DockerCommand { New-DockerResult 1 '' 'No such object' }
        $r = Test-ContainerRecreateLikely -DockerPath 'docker'
        $r.ContainerExists | Should -BeFalse
        $r.Likely | Should -BeFalse
    }

    It 'Predicts a recreate when the image changed' {
        Mock Invoke-DockerCommand {
            $line = $Arguments -join ' '
            if ($line -like 'image inspect*') { return New-DockerResult 0 "sha256:new`n" }
            if ($line -like '*Config.Env*') { return New-DockerResult 0 "ENABLE_MOBILE_ACCESS=0`n" }
            return New-DockerResult 0 "sha256:old`n"
        }
        $r = Test-ContainerRecreateLikely -DockerPath 'docker' -MobileAccess $false
        $r.ContainerExists | Should -BeTrue
        $r.Likely | Should -BeTrue
        $r.Reason | Should -Match 'image'
    }

    It 'Predicts a recreate when the mobile access setting changed' {
        Mock Invoke-DockerCommand {
            $line = $Arguments -join ' '
            if ($line -like '*Config.Env*') { return New-DockerResult 0 "USER_NAME=u`nENABLE_MOBILE_ACCESS=0`n" }
            return New-DockerResult 0 "sha256:same`n"
        }
        $r = Test-ContainerRecreateLikely -DockerPath 'docker' -MobileAccess $true
        $r.Likely | Should -BeTrue
        $r.Reason | Should -Match 'mobile'
    }

    It 'Predicts no recreate when nothing changed' {
        Mock Invoke-DockerCommand {
            $line = $Arguments -join ' '
            if ($line -like '*Config.Env*') { return New-DockerResult 0 "ENABLE_MOBILE_ACCESS=1`n" }
            return New-DockerResult 0 "sha256:same`n"
        }
        $r = Test-ContainerRecreateLikely -DockerPath 'docker' -MobileAccess $true
        $r.Likely | Should -BeFalse
    }

    It 'Treats a missing image as a likely recreate (cannot rule it out)' {
        Mock Invoke-DockerCommand {
            $line = $Arguments -join ' '
            if ($line -like 'image inspect*') { return New-DockerResult 1 '' 'No such image' }
            return New-DockerResult 0 "sha256:old`n"
        }
        (Test-ContainerRecreateLikely -DockerPath 'docker').Likely | Should -BeTrue
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

Describe 'Rebuild and uninstall paths run the rescue scan' {
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

    It 'The helpers uninstall needs are extracted next to it' {
        $complete = Get-Content "$PSScriptRoot/../scripts/AI_Docker_Complete.ps1" -Raw
        $complete | Should -Match "\`$dockerFiles = @\([^)]*'docker_helpers\.ps1'"
        $complete | Should -Match "\`$dockerFiles = @\([^)]*'log_utils\.ps1'"
    }
}
