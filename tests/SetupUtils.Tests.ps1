#Requires -Modules Pester

BeforeAll {
    . "$PSScriptRoot/../scripts/setup_utils.ps1"
}

Describe 'Fix-LineEndings' {
    BeforeEach {
        # Fix-LineEndings looks for files relative to scriptPath:
        # - If path contains 'AI-Docker-CLI*docker-files', looks in scriptPath directly
        # - Otherwise, looks in scriptPath/../docker
        # We simulate the embedded exe path so it looks in our test dir directly
        $script:TestDockerDir = Join-Path $TestDrive 'AI-Docker-CLI' 'docker-files'
        New-Item -ItemType Directory -Path $script:TestDockerDir -Force | Out-Null
    }

    It 'Converts CRLF to LF in shell scripts' {
        $file = Join-Path $script:TestDockerDir 'entrypoint.sh'
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($file, "#!/bin/bash`r`necho hello`r`n", $utf8NoBom)
        Fix-LineEndings -scriptPath $script:TestDockerDir | Out-Null
        $content = [System.IO.File]::ReadAllText($file)
        $content | Should -Not -Match "`r"
    }

    It 'Returns $true when files were fixed' {
        $file = Join-Path $script:TestDockerDir 'entrypoint.sh'
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($file, "line1`r`nline2`r`n", $utf8NoBom)
        $result = Fix-LineEndings -scriptPath $script:TestDockerDir
        $result | Should -BeTrue
    }

    It 'Returns $false when no files need fixing' {
        $file = Join-Path $script:TestDockerDir 'entrypoint.sh'
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($file, "line1`nline2`n", $utf8NoBom)
        $result = Fix-LineEndings -scriptPath $script:TestDockerDir
        $result | Should -BeFalse
    }

    It 'Returns $false when target files do not exist' {
        $result = Fix-LineEndings -scriptPath $script:TestDockerDir
        $result | Should -BeFalse
    }
}

Describe 'Replace-PasswordWithPlaceholder' {
    BeforeEach {
        $secretsDir = Join-Path $TestDrive '.secrets'
        New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    }

    It 'Replaces password content with SETUP_COMPLETE' {
        $file = Join-Path $TestDrive '.secrets' 'password.txt'
        Set-Content -Path $file -Value 'MySecretPassword123' -NoNewline
        Replace-PasswordWithPlaceholder -DockerPath $TestDrive
        $content = Get-Content $file -Raw
        $content | Should -Be 'SETUP_COMPLETE'
    }

    It 'Is idempotent - skips if already SETUP_COMPLETE' {
        $file = Join-Path $TestDrive '.secrets' 'password.txt'
        Set-Content -Path $file -Value 'SETUP_COMPLETE' -NoNewline
        Replace-PasswordWithPlaceholder -DockerPath $TestDrive
        $content = Get-Content $file -Raw
        $content | Should -Be 'SETUP_COMPLETE'
    }

    It 'Creates placeholder when password file does not exist' {
        # Remove the secrets dir to test full creation
        Remove-Item (Join-Path $TestDrive '.secrets') -Recurse -Force
        Replace-PasswordWithPlaceholder -DockerPath $TestDrive
        $file = Join-Path $TestDrive '.secrets' 'password.txt'
        $file | Should -Exist
        Get-Content $file -Raw | Should -Be 'SETUP_COMPLETE'
    }

    It 'Creates .secrets directory if missing' {
        Remove-Item (Join-Path $TestDrive '.secrets') -Recurse -Force
        Replace-PasswordWithPlaceholder -DockerPath $TestDrive
        Join-Path $TestDrive '.secrets' | Should -Exist
    }
}

Describe 'Test-NpmFunctional' {
    It 'Returns Valid=$false with NeedsInstall when npm not found' {
        Mock Get-Command { $null }
        $result = Test-NpmFunctional
        $result.Valid | Should -BeFalse
        $result.NeedsInstall | Should -BeTrue
        $result.Error | Should -Match 'not found'
    }

    It 'Returns Valid=$true with version when npm works' -Skip:(-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        # Only runs if npm is actually installed on the CI runner
        $result = Test-NpmFunctional
        $result.Valid | Should -BeTrue
        $result.Version | Should -Not -BeNullOrEmpty
    }

    It 'Returns hashtable with expected keys on failure' {
        Mock Get-Command { $null }
        $result = Test-NpmFunctional
        $result | Should -BeOfType [hashtable]
        $result.ContainsKey('Valid') | Should -BeTrue
        $result.ContainsKey('Error') | Should -BeTrue
    }

    It 'Returns NeedsRepair when npm execution throws' {
        Mock Get-Command { [PSCustomObject]@{ Source = '/usr/bin/npm' } }
        Mock npm { throw 'execution failed' }
        $result = Test-NpmFunctional
        $result.Valid | Should -BeFalse
        $result.NeedsRepair | Should -BeTrue
    }
}

Describe 'Repair-NpmInstallation' {
    It 'Returns result from Test-NpmFunctional' {
        Mock Get-Command { $null }
        Mock npm { }
        $result = Repair-NpmInstallation
        # After repair attempt, it calls Test-NpmFunctional
        # With npm mocked to not exist, should return Valid=$false
        $result.Valid | Should -BeFalse
    }

    It 'Does not throw on PATH refresh failure' {
        Mock Get-Command { $null }
        Mock npm { }
        { Repair-NpmInstallation } | Should -Not -Throw
    }
}
