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
        $script:TestDockerDir = Join-Path (Join-Path $TestDrive 'AI-Docker-CLI') 'docker-files'
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
        $file = Join-Path (Join-Path $TestDrive '.secrets') 'password.txt'
        Set-Content -Path $file -Value 'MySecretPassword123' -NoNewline
        Replace-PasswordWithPlaceholder -DockerPath $TestDrive
        $content = Get-Content $file -Raw
        $content | Should -Be 'SETUP_COMPLETE'
    }

    It 'Is idempotent - skips if already SETUP_COMPLETE' {
        $file = Join-Path (Join-Path $TestDrive '.secrets') 'password.txt'
        Set-Content -Path $file -Value 'SETUP_COMPLETE' -NoNewline
        Replace-PasswordWithPlaceholder -DockerPath $TestDrive
        $content = Get-Content $file -Raw
        $content | Should -Be 'SETUP_COMPLETE'
    }

    It 'Creates placeholder when password file does not exist' {
        # Remove the secrets dir to test full creation
        Remove-Item (Join-Path $TestDrive '.secrets') -Recurse -Force
        Replace-PasswordWithPlaceholder -DockerPath $TestDrive
        $file = Join-Path (Join-Path $TestDrive '.secrets') 'password.txt'
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
        Mock Get-Command { [pscustomobject]@{ Source = 'TestDrive:\broken-npm' } }
        $result = Test-NpmFunctional
        $result.Valid | Should -BeFalse
        $result.NeedsRepair | Should -BeTrue
    }
}

Describe 'Repair-NpmInstallation' {
    It 'Returns Valid=$false when npm not available' {
        Mock Get-Command { $null }
        $result = Repair-NpmInstallation
        # With Get-Command mocked to return null, Test-NpmFunctional returns NeedsInstall
        $result.Valid | Should -BeFalse
    }

    It 'Does not throw on PATH refresh failure' {
        Mock Get-Command { $null }
        { Repair-NpmInstallation } | Should -Not -Throw
    }
}

Describe 'New-SecurePasswordFile' {
    It 'Creates password file with correct content' {
        $dockerPath = Join-Path $TestDrive 'docker-test'
        New-Item -ItemType Directory -Path $dockerPath -Force | Out-Null
        $result = New-SecurePasswordFile -Password 'testpass123' -DockerPath $dockerPath
        $content = [System.IO.File]::ReadAllText($result)
        $content | Should -Be 'testpass123'
    }

    It 'Creates .secrets directory if missing' {
        $dockerPath = Join-Path $TestDrive 'docker-test2'
        New-SecurePasswordFile -Password 'pass' -DockerPath $dockerPath | Out-Null
        Join-Path $dockerPath '.secrets' | Should -Exist
    }

    It 'Returns path to created file' {
        $dockerPath = Join-Path $TestDrive 'docker-test3'
        $result = New-SecurePasswordFile -Password 'pass' -DockerPath $dockerPath
        $result | Should -Not -BeNullOrEmpty
        $result | Should -Exist
        $result | Should -BeLike '*.secrets*password.txt'
    }

    It 'Sets restrictive ACL permissions' -Skip:(-not $IsWindows) {
        $dockerPath = Join-Path $TestDrive 'docker-test4'
        $result = New-SecurePasswordFile -Password 'pass' -DockerPath $dockerPath
        $acl = Get-Acl $result
        # Should have inheritance disabled
        $acl.AreAccessRulesProtected | Should -BeTrue
    }
}

Describe 'Resolve-DockerFilesPath' {
    It 'Returns the script path itself for embedded exe layout' {
        $path = 'C:\Users\test\AppData\Local\AI-Docker-CLI\docker-files'
        Resolve-DockerFilesPath -ScriptPath $path | Should -Be $path
    }

    It 'Returns ..\docker for the project layout' {
        # Use an existing path so Join-Path works cross-platform in the test
        $path = Join-Path $TestDrive 'scripts'
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $result = Resolve-DockerFilesPath -ScriptPath $path
        $result | Should -Be (Join-Path $path '..\docker')
    }
}

Describe 'Get-ComposeFileArgs' {
    It 'Uses only the base compose file when mobile access is disabled' {
        Get-ComposeFileArgs -DockerPath $TestDrive -MobileAccess $false |
            Should -Be 'compose -f docker-compose.yml'
    }

    It 'Adds the mobile override when mobile access is enabled' {
        $mobileOverride = Join-Path $TestDrive 'docker-compose.mobile.yml'
        Set-Content -Path $mobileOverride -Value 'services: {}'
        Get-ComposeFileArgs -DockerPath $TestDrive -MobileAccess $true |
            Should -Be 'compose -f docker-compose.yml -f docker-compose.mobile.yml'
        Remove-Item $mobileOverride -Force
    }

    It 'Fails when mobile access is enabled without the override file' {
        { Get-ComposeFileArgs -DockerPath $TestDrive -MobileAccess $true } |
            Should -Throw '*docker-compose.mobile.yml*'
    }
}

Describe 'Test-PasswordStrength' {
    It 'Rejects empty password' {
        (Test-PasswordStrength -Password '').Valid | Should -BeFalse
    }

    It 'Rejects passwords shorter than 8 characters' {
        $result = Test-PasswordStrength -Password 'ab1'
        $result.Valid | Should -BeFalse
        $result.Message | Should -Match '8 characters'
    }

    It 'Rejects passwords without a digit' {
        $result = Test-PasswordStrength -Password 'abcdefgh'
        $result.Valid | Should -BeFalse
        $result.Message | Should -Match 'letter and one digit'
    }

    It 'Rejects passwords without a letter' {
        (Test-PasswordStrength -Password '12345678').Valid | Should -BeFalse
    }

    It 'Accepts a password with 8+ chars, a letter, and a digit' {
        (Test-PasswordStrength -Password 'passw0rd').Valid | Should -BeTrue
    }

    It 'Accepts symbols alongside the requirements' {
        (Test-PasswordStrength -Password 'P@ssw0rd!123').Valid | Should -BeTrue
    }
}
