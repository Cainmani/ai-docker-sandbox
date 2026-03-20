#Requires -Modules Pester

BeforeAll {
    . "$PSScriptRoot/../scripts/log_utils.ps1"
}

Describe 'Sanitize-LogMessage' {
    It 'Passes clean messages through unchanged' {
        Sanitize-LogMessage -Message 'Hello world' | Should -Be 'Hello world'
    }

    It 'Returns empty string for empty input' {
        Sanitize-LogMessage -Message '' | Should -Be ''
    }

    It 'Returns null for null input' {
        Sanitize-LogMessage -Message $null | Should -BeNullOrEmpty
    }

    It 'Redacts OpenAI sk-proj- keys' {
        $msg = 'key is sk-proj-abcdefghijklmnopqrstuvwx'
        Sanitize-LogMessage -Message $msg | Should -Be 'key is <REDACTED_API_KEY>'
    }

    It 'Redacts generic sk- keys' {
        $msg = 'key is sk-abcdefghijklmnopqrstuvwx'
        Sanitize-LogMessage -Message $msg | Should -Be 'key is <REDACTED_API_KEY>'
    }

    It 'Redacts Anthropic sk-ant- keys' {
        $msg = 'key is sk-ant-api03-abcdefghijklmnopqrstuvwx'
        Sanitize-LogMessage -Message $msg | Should -Be 'key is <REDACTED_API_KEY>'
    }

    It 'Redacts GitHub tokens (ghp_)' {
        $token = 'ghp_' + ('A' * 36)
        $msg = "token: $token"
        Sanitize-LogMessage -Message $msg | Should -Be 'token: <REDACTED_TOKEN>'
    }

    It 'Redacts GitHub tokens (ghs_)' {
        $token = 'ghs_' + ('B' * 36)
        $msg = "found $token here"
        Sanitize-LogMessage -Message $msg | Should -Be 'found <REDACTED_TOKEN> here'
    }

    It 'Redacts fine-grained GitHub tokens (github_pat_)' {
        $token = 'github_pat_' + ('C' * 22)
        $msg = "pat: $token"
        Sanitize-LogMessage -Message $msg | Should -Be 'pat: <REDACTED_TOKEN>'
    }

    It 'Redacts password values' {
        Sanitize-LogMessage -Message 'Password=mysecret123' | Should -Be 'Password=<REDACTED>'
        Sanitize-LogMessage -Message 'password: hunter2' | Should -Be 'password=<REDACTED>'
    }

    It 'Redacts token values' {
        $msg = 'Token=abcdefghijklmnopqrstuvwxyz1234'
        Sanitize-LogMessage -Message $msg | Should -Be 'Token=<REDACTED>'
    }

    It 'Redacts secret values' {
        $msg = 'Secret=abcdefghijklmnopqrstuvwxyz1234'
        Sanitize-LogMessage -Message $msg | Should -Be 'Secret=<REDACTED>'
    }

    It 'Redacts AWS access keys' {
        $msg = 'aws key AKIAIOSFODNN7EXAMPLE found'
        Sanitize-LogMessage -Message $msg | Should -Be 'aws key <REDACTED_AWS_KEY> found'
    }

    It 'Redacts Google Cloud API keys' {
        $key = 'AIza' + ('x' * 35)
        $msg = "gcp key $key here"
        Sanitize-LogMessage -Message $msg | Should -Be 'gcp key <REDACTED_GCP_KEY> here'
    }

    It 'Redacts Bearer tokens' {
        $token = 'A' * 30
        $msg = "Authorization: Bearer $token"
        Sanitize-LogMessage -Message $msg | Should -Be 'Authorization: Bearer <REDACTED>'
    }

    It 'Redacts JWT tokens' {
        $msg = 'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U'
        $result = Sanitize-LogMessage -Message $msg
        $result | Should -Be 'token <REDACTED_JWT>'
    }

    It 'Redacts container username when set' {
        $script:ContainerUsername = 'testuser42'
        $msg = 'Created user testuser42 in container'
        $result = Sanitize-LogMessage -Message $msg
        $result | Should -Be 'Created user <USER> in container'
        $script:ContainerUsername = $null
    }

    It 'Does not redact container username when not set' {
        $script:ContainerUsername = $null
        $msg = 'Created user testuser42 in container'
        Sanitize-LogMessage -Message $msg | Should -Be $msg
    }

    It 'Handles multiple redactions in one message' {
        $msg = 'key sk-proj-abcdefghijklmnopqrstuvwx and Password=secret'
        $result = Sanitize-LogMessage -Message $msg
        $result | Should -Be 'key <REDACTED_API_KEY> and Password=<REDACTED>'
    }
}

Describe 'Write-AppLog' {
    BeforeAll {
        $script:TestLogFile = Join-Path $TestDrive 'test.log'
        $script:LogFile = $script:TestLogFile
    }

    BeforeEach {
        if (Test-Path $script:TestLogFile) { Remove-Item $script:TestLogFile }
    }

    It 'Writes a log entry to the log file' {
        Write-AppLog -Message 'Test message' -Component 'TEST'
        $script:TestLogFile | Should -Exist
        $content = Get-Content $script:TestLogFile -Raw
        $content | Should -Match '\[INFO\] \[TEST\] Test message'
    }

    It 'Includes timestamp in log entry' {
        Write-AppLog -Message 'Timestamp test' -Component 'TEST'
        $content = Get-Content $script:TestLogFile -Raw
        $content | Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\]'
    }

    It 'Uses specified log level' {
        Write-AppLog -Message 'Warning test' -Level 'WARN' -Component 'TEST'
        $content = Get-Content $script:TestLogFile -Raw
        $content | Should -Match '\[WARN\] \[TEST\] Warning test'
    }

    It 'Defaults to INFO level' {
        Write-AppLog -Message 'Default level' -Component 'TEST'
        $content = Get-Content $script:TestLogFile -Raw
        $content | Should -Match '\[INFO\]'
    }

    It 'Defaults to APP component' {
        Write-AppLog -Message 'Default component'
        $content = Get-Content $script:TestLogFile -Raw
        $content | Should -Match '\[APP\]'
    }

    It 'Sanitizes messages before writing' {
        Write-AppLog -Message 'key sk-proj-abcdefghijklmnopqrstuvwx' -Component 'TEST'
        $content = Get-Content $script:TestLogFile -Raw
        $content | Should -Match '<REDACTED_API_KEY>'
        $content | Should -Not -Match 'sk-proj-'
    }

    It 'Does not throw on write failure' {
        $script:LogFile = '/nonexistent/path/log.txt'
        { Write-AppLog -Message 'Should not throw' -Component 'TEST' } | Should -Not -Throw
        $script:LogFile = $script:TestLogFile
    }
}
