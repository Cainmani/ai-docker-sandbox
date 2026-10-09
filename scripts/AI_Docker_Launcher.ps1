# Developer entry point for the released implementation; build an EXE first.
$script:AppVersion = "1.7.0"  # Keep in sync with root VERSION file
$root = Split-Path -Parent $PSScriptRoot
$candidates = @(Join-Path $root "AI_Docker_Manager_v$script:AppVersion.exe")
$candidates += Join-Path $root "dist\AI_Docker_Manager_v$script:AppVersion.exe"
$candidates += Join-Path $root 'dist\AI_Docker_Manager.exe'
$exe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $exe) { throw 'Build the manager using scripts\build\build_complete_exe.ps1, then run this developer wrapper.' }
Start-Process -FilePath $exe
