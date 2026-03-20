#Requires -Modules Pester

BeforeAll {
    . "$PSScriptRoot/../scripts/env_utils.ps1"
}

Describe 'Read-EnvFile' {
    It 'Parses key=value pairs' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value "USER_NAME=devuser`nWORKSPACE_PATH=C:\code"
        $result = Read-EnvFile -Path $file
        $result['USER_NAME'] | Should -Be 'devuser'
        $result['WORKSPACE_PATH'] | Should -Be 'C:\code'
    }

    It 'Ignores comment lines' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value "# comment`nUSER_NAME=testuser"
        $result = Read-EnvFile -Path $file
        $result.Count | Should -Be 1
        $result['USER_NAME'] | Should -Be 'testuser'
    }

    It 'Ignores empty lines' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value "USER_NAME=testuser`n`nPORT=3000"
        $result = Read-EnvFile -Path $file
        $result.Count | Should -Be 2
    }

    It 'Returns empty hashtable for missing file' {
        $result = Read-EnvFile -Path (Join-Path $TestDrive 'nonexistent.env')
        $result.Count | Should -Be 0
    }

    It 'Handles values with equals signs' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value "SOME_VAR=value=with=equals"
        $result = Read-EnvFile -Path $file
        $result['SOME_VAR'] | Should -Be 'value=with=equals'
    }

    It 'Handles indented comments' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value "  # indented comment`nKEY=val"
        $result = Read-EnvFile -Path $file
        $result.Count | Should -Be 1
    }
}

Describe 'Get-EnvVar' {
    It 'Returns value when key exists' {
        $env = @{ 'USER_NAME' = 'devuser' }
        $result = Get-EnvVar -EnvData $env -Name 'USER_NAME'
        $result.Found | Should -BeTrue
        $result.Value | Should -Be 'devuser'
        $result.Valid | Should -BeTrue
    }

    It 'Returns default when key missing' {
        $env = @{}
        $result = Get-EnvVar -EnvData $env -Name 'PORT' -Default '3000'
        $result.Found | Should -BeFalse
        $result.Value | Should -Be '3000'
    }

    It 'Returns null when key missing and no default' {
        $env = @{}
        $result = Get-EnvVar -EnvData $env -Name 'MISSING'
        $result.Found | Should -BeFalse
        $result.Value | Should -BeNullOrEmpty
        $result.Valid | Should -BeFalse
    }

    It 'Validates against pattern - valid' {
        $env = @{ 'USER_NAME' = 'devuser' }
        $result = Get-EnvVar -EnvData $env -Name 'USER_NAME' -ValidationPattern '^[a-z_][a-z0-9_-]{0,31}$'
        $result.Valid | Should -BeTrue
    }

    It 'Validates against pattern - invalid' {
        $env = @{ 'USER_NAME' = 'INVALID USER!' }
        $result = Get-EnvVar -EnvData $env -Name 'USER_NAME' -ValidationPattern '^[a-z_][a-z0-9_-]{0,31}$'
        $result.Valid | Should -BeFalse
        $result.Value | Should -Be 'INVALID USER!'
    }

    It 'Skips validation when no pattern provided' {
        $env = @{ 'ANYTHING' = '!@#$%' }
        $result = Get-EnvVar -EnvData $env -Name 'ANYTHING'
        $result.Valid | Should -BeTrue
    }
}
