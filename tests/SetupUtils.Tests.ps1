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
