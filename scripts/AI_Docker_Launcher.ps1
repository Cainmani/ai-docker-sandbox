# Developer entry point: the same embedded implementation without ps2exe.
$script:AppVersion = "1.7.0"  # Keep in sync with root VERSION file
Push-Location (Join-Path $PSScriptRoot 'build')
try { & .\build_complete_exe.ps1 -SourceOnly } finally { Pop-Location }
