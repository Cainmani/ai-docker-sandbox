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

    It 'Strips double quotes from values' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value 'WORKSPACE_PATH="C:\My Code\project"'
        $result = Read-EnvFile -Path $file
        $result['WORKSPACE_PATH'] | Should -Be 'C:\My Code\project'
    }

    It 'Strips single quotes from values' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value "TOKEN='abc 123'"
        $result = Read-EnvFile -Path $file
        $result['TOKEN'] | Should -Be 'abc 123'
    }

    It 'Does not strip mismatched quotes' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value "ODD=`"half-quoted"
        $result = Read-EnvFile -Path $file
        $result['ODD'] | Should -Be '"half-quoted'
    }

    It 'Preserves inner quotes' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value "MSG=`"say 'hi'`""
        $result = Read-EnvFile -Path $file
        $result['MSG'] | Should -Be "say 'hi'"
    }

    It 'Leaves a lone quote character untouched' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -Path $file -Value 'Q="'
        $result = Read-EnvFile -Path $file
        $result['Q'] | Should -Be '"'
    }
}

Describe 'ConvertFrom-EnvValue' {
    It 'Strips matching double quotes' {
        ConvertFrom-EnvValue -Value '"hello"' | Should -Be 'hello'
    }

    It 'Strips matching single quotes' {
        ConvertFrom-EnvValue -Value "'hello'" | Should -Be 'hello'
    }

    It 'Leaves unquoted values alone' {
        ConvertFrom-EnvValue -Value 'plain' | Should -Be 'plain'
    }

    It 'Handles empty string' {
        ConvertFrom-EnvValue -Value '' | Should -Be ''
    }

    It 'Strips quotes to empty string for ""' {
        ConvertFrom-EnvValue -Value '""' | Should -Be ''
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

Describe 'Test-PortValue' {
    It 'Accepts a typical port' {
        Test-PortValue -Port '3000' | Should -BeTrue
    }

    It 'Accepts integer input' {
        Test-PortValue -Port 8080 | Should -BeTrue
    }

    It 'Accepts boundary ports 1 and 65535' {
        Test-PortValue -Port '1' | Should -BeTrue
        Test-PortValue -Port '65535' | Should -BeTrue
    }

    It 'Rejects 0' {
        Test-PortValue -Port '0' | Should -BeFalse
    }

    It 'Rejects ports above 65535' {
        Test-PortValue -Port '65536' | Should -BeFalse
        Test-PortValue -Port '99999' | Should -BeFalse
    }

    It 'Rejects negative numbers' {
        Test-PortValue -Port '-80' | Should -BeFalse
    }

    It 'Rejects non-numeric input' {
        Test-PortValue -Port 'abc' | Should -BeFalse
        Test-PortValue -Port '80a' | Should -BeFalse
    }

    It 'Rejects empty and null' {
        Test-PortValue -Port '' | Should -BeFalse
        Test-PortValue -Port $null | Should -BeFalse
    }

    It 'Trims surrounding whitespace' {
        Test-PortValue -Port ' 3000 ' | Should -BeTrue
    }
}

Describe 'Set-EnvKey' {
    It 'Adds a new key to a new file' {
        $file = Join-Path $TestDrive 'set1.env'
        Set-EnvKey -Path $file -Key 'PORT' -Value '3000' | Should -BeTrue
        (Read-EnvFile -Path $file)['PORT'] | Should -Be '3000'
    }

    It 'Updates an existing key in place' {
        $file = Join-Path $TestDrive 'set2.env'
        Set-Content -Path $file -Value "A=1`nPORT=3000`nB=2"
        Set-EnvKey -Path $file -Key 'PORT' -Value '4000' | Should -BeTrue
        $data = Read-EnvFile -Path $file
        $data['PORT'] | Should -Be '4000'
        $data['A'] | Should -Be '1'
        $data['B'] | Should -Be '2'
    }

    It 'Preserves comments and ordering' {
        $file = Join-Path $TestDrive 'set3.env'
        Set-Content -Path $file -Value "# header comment`nA=1`n`nPORT=3000"
        Set-EnvKey -Path $file -Key 'PORT' -Value '5000' | Should -BeTrue
        $lines = @(Get-Content $file)
        $lines[0] | Should -Be '# header comment'
        $lines[1] | Should -Be 'A=1'
        $lines[3] | Should -Be 'PORT=5000'
    }

    It 'Quotes values containing spaces so they round-trip' {
        $file = Join-Path $TestDrive 'set4.env'
        Set-EnvKey -Path $file -Key 'WORKSPACE_PATH' -Value 'C:\My Code\proj' | Should -BeTrue
        (Get-Content $file -Raw) | Should -Match 'WORKSPACE_PATH="C:\\My Code\\proj"'
        (Read-EnvFile -Path $file)['WORKSPACE_PATH'] | Should -Be 'C:\My Code\proj'
    }

    It 'Does not touch keys sharing a prefix' {
        $file = Join-Path $TestDrive 'set5.env'
        Set-Content -Path $file -Value "PORT=1`nPORT_EXTRA=2"
        Set-EnvKey -Path $file -Key 'PORT' -Value '9' | Should -BeTrue
        $data = Read-EnvFile -Path $file
        $data['PORT'] | Should -Be '9'
        $data['PORT_EXTRA'] | Should -Be '2'
    }

    It 'Allows empty value' {
        $file = Join-Path $TestDrive 'set6.env'
        Set-EnvKey -Path $file -Key 'EMPTY' -Value '' | Should -BeTrue
        (Get-Content $file -Raw) | Should -Match 'EMPTY='
    }

    It 'Rejects invalid key names' {
        $file = Join-Path $TestDrive 'set7.env'
        { Set-EnvKey -Path $file -Key 'BAD KEY' -Value 'x' } | Should -Throw
    }

    It 'Leaves no temp files behind' {
        $file = Join-Path $TestDrive 'set8.env'
        Set-EnvKey -Path $file -Key 'A' -Value '1' | Should -BeTrue
        @(Get-ChildItem $TestDrive -Filter 'set8.env.tmp.*').Count | Should -Be 0
    }
}

Describe 'Remove-EnvKey' {
    It 'Removes an existing key' {
        $file = Join-Path $TestDrive 'rm1.env'
        Set-Content -Path $file -Value "A=1`nB=2`nC=3"
        Remove-EnvKey -Path $file -Key 'B' | Should -BeTrue
        $data = Read-EnvFile -Path $file
        $data.ContainsKey('B') | Should -BeFalse
        $data['A'] | Should -Be '1'
        $data['C'] | Should -Be '3'
    }

    It 'Returns true when key is absent' {
        $file = Join-Path $TestDrive 'rm2.env'
        Set-Content -Path $file -Value "A=1"
        Remove-EnvKey -Path $file -Key 'MISSING' | Should -BeTrue
        (Read-EnvFile -Path $file)['A'] | Should -Be '1'
    }

    It 'Returns true when file is missing' {
        Remove-EnvKey -Path (Join-Path $TestDrive 'nope.env') -Key 'X' | Should -BeTrue
    }

    It 'Preserves comments when removing' {
        $file = Join-Path $TestDrive 'rm3.env'
        Set-Content -Path $file -Value "# keep me`nA=1`nGONE=x"
        Remove-EnvKey -Path $file -Key 'GONE' | Should -BeTrue
        (Get-Content $file -Raw) | Should -Match '# keep me'
        (Get-Content $file -Raw) | Should -Not -Match 'GONE='
    }

    It 'Rejects invalid key names' {
        { Remove-EnvKey -Path (Join-Path $TestDrive 'rm4.env') -Key 'BAD KEY' } | Should -Throw
    }
}
