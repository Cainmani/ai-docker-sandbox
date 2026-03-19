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
        Mock Start-Process { [PSCustomObject]@{ ExitCode = 0 } }
        DockerOk | Should -BeTrue
    }

    It 'Returns false when Find-Docker returns null' {
        Mock Find-Docker { $null }
        DockerOk | Should -BeFalse
    }

    It 'Returns false when docker info fails' {
        Mock Find-Docker { 'C:\docker.exe' }
        Mock Start-Process { [PSCustomObject]@{ ExitCode = 1 } }
        DockerOk | Should -BeFalse
    }

    It 'Returns false and handles exception gracefully' {
        Mock Find-Docker { throw 'connection failed' }
        DockerOk | Should -BeFalse
    }
}
