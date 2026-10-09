BeforeAll {
    . "$PSScriptRoot/../scripts/agent_helpers.ps1"
}
Describe 'Agent arguments and protocol' {
    It 'Rejects paths outside the workspace and parent traversal' {
        { ConvertTo-AgentFolder '/tmp/project' } | Should -Throw
        { ConvertTo-AgentFolder '/workspace/../private' } | Should -Throw
        { ConvertTo-AgentFolder "/workspace/project`nnext" } | Should -Throw
    }
    It 'Accepts special characters as folder data' {
        $folder = '/workspace/λ spaces '' $ ; % ^ ! " & |'
        ConvertTo-AgentFolder $folder | Should -BeExactly $folder
    }
    It 'Ignores account identifiers and arbitrary status output' {
        $values = ConvertFrom-AgentProtocol "AUTH_codex=ready`nemail=user@example.invalid`nTOKEN=secret`nUPDATE_RESULT=updated`nERROR=workspace-stopped"
        $values.Count | Should -Be 3
        $values.AUTH_codex | Should -Be 'ready'
        $values.ERROR | Should -Be 'workspace-stopped'
    }
    It 'Quotes empty arguments and trailing backslashes' {
        ConvertTo-NativeArgument '' | Should -BeExactly '""'
        ConvertTo-NativeArgument 'C:\space path\' | Should -BeExactly '"C:\space path\\"'
    }
    It 'Round-trips hostile arguments through a native child without a command shell' {
        $receiver = Join-Path $TestDrive 'receiver.ps1'
        [IO.File]::WriteAllText($receiver, 'param([string]$Value) [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false); [Console]::Out.Write($Value)')
        $executable = (Get-Process -Id $PID).Path
        foreach ($value in @('λ spaces '' $ ; % ^ ! " & |', 'ends\', '', 'two\\"quotes')) {
            $process = New-AgentProcess $executable @('-NoProfile','-ExecutionPolicy','Bypass','-File',$receiver,'-Value',$value) -Capture
            try {
                $output = $process.StandardOutput.ReadToEndAsync()
                $errorOutput = $process.StandardError.ReadToEndAsync()
                $process.WaitForExit(15000) | Should -BeTrue
                $process.ExitCode | Should -Be 0
                $output.Result | Should -BeExactly $value
            } finally { $process.Dispose() }
        }
    }
}
Describe 'Inspected container compatibility' {
    BeforeEach {
        $script:InspectFixture = @{
            Config = @{ Image='ai-docker-cli:latest'; Env=@('USER_NAME=alice'); Labels=@{'ai-docker.version'='1.7.0'} }
            State = @{ Running=$true }
            Mounts = @(@{Type='bind';Destination='/workspace';Source='C:\actual-workspace'})
            Id='container-a'
        }
        Mock New-AgentProcess {
            $text = $script:InspectFixture | ConvertTo-Json -Depth 8 -Compress
            $reader = [pscustomobject]@{ Value=$text }
            $reader | Add-Member ScriptMethod ReadToEndAsync { @{Result=$this.Value} }
            $process = [pscustomobject]@{ExitCode=0;StandardOutput=$reader;StandardError=$reader}
            $process | Add-Member ScriptMethod WaitForExit { $true }
            $process | Add-Member ScriptMethod Dispose {}
            $process
        }
    }
    It 'Reads the actual mount/user and gates new support from the image label' {
        $context = Get-AgentContainer 'docker'
        $context.Source | Should -Be 'C:\actual-workspace'
        $context.User | Should -Be 'alice'
        $context.Supported | Should -BeTrue
    }
    It 'Keeps old and unknown images on the legacy route' {
        foreach ($version in @('1.6.0','0.0.0','unknown','')) {
            $script:InspectFixture.Config.Labels['ai-docker.version']=$version
            (Get-AgentContainer 'docker').Supported | Should -BeFalse
        }
    }
    It 'Rejects an unexpected image, invalid user or missing workspace mount' {
        $script:InspectFixture.Config.Image='unrelated:latest'
        { Get-AgentContainer 'docker' } | Should -Throw
        $script:InspectFixture.Config.Image='ai-docker-cli:latest'
        $script:InspectFixture.Config.Env=@('USER_NAME=alice;echo injected')
        { Get-AgentContainer 'docker' } | Should -Throw
        $script:InspectFixture.Config.Env=@('USER_NAME=alice')
        $script:InspectFixture.Mounts=@()
        { Get-AgentContainer 'docker' } | Should -Throw
    }
}
