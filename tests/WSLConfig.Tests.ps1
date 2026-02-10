#Requires -Modules Pester

BeforeAll {
    . "$PSScriptRoot/../scripts/wsl_config.ps1"
}

Describe 'Get-SystemMemoryGB' {
    It 'Returns correct GB for a 16GB system' {
        Mock Get-CimInstance {
            [PSCustomObject]@{ TotalPhysicalMemory = 17179869184 }
        }
        Get-SystemMemoryGB | Should -Be 16
    }

    It 'Returns correct GB for an 8GB system' {
        Mock Get-CimInstance {
            [PSCustomObject]@{ TotalPhysicalMemory = 8589934592 }
        }
        Get-SystemMemoryGB | Should -Be 8
    }

    It 'Rounds to one decimal place' {
        # 12.8 GB = 13743895347 bytes
        Mock Get-CimInstance {
            [PSCustomObject]@{ TotalPhysicalMemory = 13743895347 }
        }
        Get-SystemMemoryGB | Should -Be 12.8
    }

    It 'Returns default 8 on WMI failure' {
        Mock Get-CimInstance { throw 'WMI unavailable' }
        Get-SystemMemoryGB | Should -Be 8
    }
}

Describe 'Get-ProcessorCount' {
    It 'Returns count for single CPU' {
        Mock Get-CimInstance {
            [PSCustomObject]@{ NumberOfLogicalProcessors = 8 }
        }
        Get-ProcessorCount | Should -Be 8
    }

    It 'Returns summed count for multi-CPU (regression for bug 2)' {
        Mock Get-CimInstance {
            @(
                [PSCustomObject]@{ NumberOfLogicalProcessors = 8 },
                [PSCustomObject]@{ NumberOfLogicalProcessors = 8 }
            )
        }
        Get-ProcessorCount | Should -Be 16
    }

    It 'Falls back to [Environment]::ProcessorCount on null' {
        Mock Get-CimInstance {
            [PSCustomObject]@{ NumberOfLogicalProcessors = $null }
        }
        $expected = [Environment]::ProcessorCount
        Get-ProcessorCount | Should -Be $expected
    }

    It 'Returns default 4 on WMI failure' {
        Mock Get-CimInstance { throw 'WMI unavailable' }
        Get-ProcessorCount | Should -Be 4
    }
}

Describe 'Get-RecommendedWSLProfile' {
    It 'Returns light for 8GB' {
        Get-RecommendedWSLProfile -TotalRAMGB 8 | Should -Be 'light'
    }

    It 'Returns light for 10GB (boundary)' {
        Get-RecommendedWSLProfile -TotalRAMGB 10 | Should -Be 'light'
    }

    It 'Returns standard for 11GB (boundary)' {
        Get-RecommendedWSLProfile -TotalRAMGB 11 | Should -Be 'standard'
    }

    It 'Returns standard for 16GB' {
        Get-RecommendedWSLProfile -TotalRAMGB 16 | Should -Be 'standard'
    }

    It 'Returns standard for 20GB (boundary)' {
        Get-RecommendedWSLProfile -TotalRAMGB 20 | Should -Be 'standard'
    }

    It 'Returns heavy for 21GB (boundary)' {
        Get-RecommendedWSLProfile -TotalRAMGB 21 | Should -Be 'heavy'
    }

    It 'Returns heavy for 64GB' {
        Get-RecommendedWSLProfile -TotalRAMGB 64 | Should -Be 'heavy'
    }

    It 'Returns light for 0GB (edge case)' {
        Get-RecommendedWSLProfile -TotalRAMGB 0 | Should -Be 'light'
    }
}

Describe 'Get-ProfileDisplayName' {
    It 'Returns LIGHT for light' {
        Get-ProfileDisplayName -Profile 'light' | Should -Be 'LIGHT'
    }

    It 'Returns STANDARD for standard' {
        Get-ProfileDisplayName -Profile 'standard' | Should -Be 'STANDARD'
    }

    It 'Returns HEAVY for heavy' {
        Get-ProfileDisplayName -Profile 'heavy' | Should -Be 'HEAVY'
    }

    It 'Returns STANDARD for unknown profile' {
        Get-ProfileDisplayName -Profile 'turbo' | Should -Be 'STANDARD'
    }

    It 'Returns STANDARD for empty string' {
        Get-ProfileDisplayName -Profile '' | Should -Be 'STANDARD'
    }
}

Describe 'New-WSLConfig' {
    It 'Creates correct light profile' {
        $path = Join-Path $TestDrive '.wslconfig'
        New-WSLConfig -Profile 'light' -Path $path -SystemCores 8 | Should -Be $true
        $content = Get-Content $path -Raw
        $content | Should -Match 'memory=3GB'
        $content | Should -Match 'swap=2GB'
        $content | Should -Match 'processors=2'
    }

    It 'Creates correct standard profile' {
        $path = Join-Path $TestDrive '.wslconfig'
        New-WSLConfig -Profile 'standard' -Path $path -SystemCores 8 | Should -Be $true
        $content = Get-Content $path -Raw
        $content | Should -Match 'memory=6GB'
        $content | Should -Match 'swap=4GB'
        $content | Should -Match 'processors=4'
    }

    It 'Creates correct heavy profile' {
        $path = Join-Path $TestDrive '.wslconfig'
        New-WSLConfig -Profile 'heavy' -Path $path -SystemCores 8 | Should -Be $true
        $content = Get-Content $path -Raw
        $content | Should -Match 'memory=12GB'
        $content | Should -Match 'swap=6GB'
        $content | Should -Match 'processors=6'
    }

    It 'Caps processors to SystemCores' {
        $path = Join-Path $TestDrive '.wslconfig'
        New-WSLConfig -Profile 'heavy' -Path $path -SystemCores 2 | Should -Be $true
        $content = Get-Content $path -Raw
        $content | Should -Match 'processors=2'
    }

    It 'Contains wizard marker comment' {
        $path = Join-Path $TestDrive '.wslconfig'
        New-WSLConfig -Profile 'standard' -Path $path | Should -Be $true
        $content = Get-Content $path -Raw
        $content | Should -Match 'Auto-generated by AI CLI Docker Setup'
    }

    It 'Contains [wsl2] section header' {
        $path = Join-Path $TestDrive '.wslconfig'
        New-WSLConfig -Profile 'standard' -Path $path | Should -Be $true
        $content = Get-Content $path -Raw
        $content | Should -Match '\[wsl2\]'
    }

    It 'Returns $false for unknown profile' {
        $path = Join-Path $TestDrive '.wslconfig'
        New-WSLConfig -Profile 'turbo' -Path $path | Should -Be $false
    }

    It 'Returns $true on success' {
        $path = Join-Path $TestDrive '.wslconfig'
        New-WSLConfig -Profile 'light' -Path $path | Should -Be $true
    }
}

Describe 'Parse-WSLConfig' {
    It 'Returns Exists=$false for missing file' {
        $path = Join-Path $TestDrive 'nonexistent.wslconfig'
        $result = Parse-WSLConfig -Path $path
        $result.Exists | Should -Be $false
    }

    It 'Parses memory correctly' {
        $path = Join-Path $TestDrive '.wslconfig'
        "[wsl2]`nmemory=6GB" | Out-File -FilePath $path -Encoding UTF8
        $result = Parse-WSLConfig -Path $path
        $result.Memory | Should -Be '6GB'
    }

    It 'Parses swap correctly' {
        $path = Join-Path $TestDrive '.wslconfig'
        "[wsl2]`nswap=4GB" | Out-File -FilePath $path -Encoding UTF8
        $result = Parse-WSLConfig -Path $path
        $result.Swap | Should -Be '4GB'
    }

    It 'Parses processors correctly' {
        $path = Join-Path $TestDrive '.wslconfig'
        "[wsl2]`nprocessors=4" | Out-File -FilePath $path -Encoding UTF8
        $result = Parse-WSLConfig -Path $path
        $result.Processors | Should -Be 4
    }

    It 'Detects wizard marker (IsOurs)' {
        $path = Join-Path $TestDrive '.wslconfig'
        "# Auto-generated by AI CLI Docker Setup`n[wsl2]`nmemory=6GB" | Out-File -FilePath $path -Encoding UTF8
        $result = Parse-WSLConfig -Path $path
        $result.IsOurs | Should -Be $true
    }

    It 'Strips inline comments (regression for bug 1)' {
        $path = Join-Path $TestDrive '.wslconfig'
        "[wsl2]`nmemory=8GB # my setting`nswap=4GB # swap size" | Out-File -FilePath $path -Encoding UTF8
        $result = Parse-WSLConfig -Path $path
        $result.Memory | Should -Be '8GB'
        $result.Swap | Should -Be '4GB'
    }

    It 'Handles CRLF line endings' {
        $path = Join-Path $TestDrive '.wslconfig'
        $content = "[wsl2]`r`nmemory=6GB`r`nswap=4GB`r`nprocessors=4"
        [System.IO.File]::WriteAllText($path, $content)
        $result = Parse-WSLConfig -Path $path
        $result.Memory | Should -Be '6GB'
        $result.Swap | Should -Be '4GB'
        $result.Processors | Should -Be 4
    }

    It 'Handles missing keys gracefully' {
        $path = Join-Path $TestDrive '.wslconfig'
        "[wsl2]`npageReporting=false" | Out-File -FilePath $path -Encoding UTF8
        $result = Parse-WSLConfig -Path $path
        $result.Exists | Should -Be $true
        $result.Memory | Should -BeNullOrEmpty
        $result.Swap | Should -BeNullOrEmpty
        $result.Processors | Should -BeNullOrEmpty
    }

    It 'Graceful failure on locked/deleted file (regression for bug 3)' {
        $path = Join-Path $TestDrive 'vanished.wslconfig'
        # File does not exist - simulates deleted file scenario
        $result = Parse-WSLConfig -Path $path
        $result.Exists | Should -Be $false
        $result.Memory | Should -BeNullOrEmpty
    }

    It 'Sets IsOurs to false for non-wizard configs' {
        $path = Join-Path $TestDrive '.wslconfig'
        "[wsl2]`nmemory=6GB" | Out-File -FilePath $path -Encoding UTF8
        $result = Parse-WSLConfig -Path $path
        $result.IsOurs | Should -Be $false
    }
}
