@echo off
echo.
echo ================================================================
echo    BUILDING AI DOCKER MANAGER EXE
echo ================================================================
echo.
echo Running build script...
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0build_complete_exe.ps1"

echo.
echo ================================================================
echo    BUILD COMPLETE!
echo ================================================================
echo.
echo Check for AI_Docker_Manager.exe in this directory.
echo.
pause
