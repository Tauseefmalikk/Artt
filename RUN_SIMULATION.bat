@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Atomic Red Team - 1-Click Simulation Runner
:: ============================================================================

title Atomic Red Team - Automated Simulation Runner

:: 1. Check for Administrative Privileges and Auto-Elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ============================================================
    echo  Requesting Administrator Privileges...
    echo ============================================================
    echo.
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: 2. Set current working directory to this script's directory
cd /d "%~dp0"

:: 3. Locate Start-ARTAutomation.ps1
set "TARGET_SCRIPT="

if exist "%~dp0ART-main\scripts\Start-ARTAutomation.ps1" (
    set "TARGET_SCRIPT=%~dp0ART-main\scripts\Start-ARTAutomation.ps1"
) else if exist "%~dp0scripts\Start-ARTAutomation.ps1" (
    set "TARGET_SCRIPT=%~dp0scripts\Start-ARTAutomation.ps1"
) else if exist "%~dp0Artt-main\ART-main\scripts\Start-ARTAutomation.ps1" (
    set "TARGET_SCRIPT=%~dp0Artt-main\ART-main\scripts\Start-ARTAutomation.ps1"
) else if exist "%~dp0..\ART-main\scripts\Start-ARTAutomation.ps1" (
    set "TARGET_SCRIPT=%~dp0..\ART-main\scripts\Start-ARTAutomation.ps1"
)

if "%TARGET_SCRIPT%"=="" (
    echo.
    echo [ERROR] Could not find Start-ARTAutomation.ps1!
    echo Please make sure the project files are intact.
    echo.
    pause
    exit /b 1
)

:: 4. Run the PowerShell automation with execution policy bypass
echo.
echo ============================================================
echo  Starting 1-Click Atomic Red Team Simulation...
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TARGET_SCRIPT%"

echo.
echo ============================================================
echo  Execution finished. Press any key to close this window.
echo ============================================================
pause >nul
