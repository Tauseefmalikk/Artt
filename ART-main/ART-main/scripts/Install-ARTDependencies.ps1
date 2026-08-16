<#
.SYNOPSIS
    Configures dependencies for the ART Automation Suite.

.DESCRIPTION
    Assumes you have already downloaded Atomic Red Team manually.
    This script:
    - Imports the Invoke-AtomicRedTeam module from your local folder
    - Installs ImportExcel module (for Excel reports, no Office needed)
    - Validates everything is ready to run

.PARAMETER AtomicsPath
    Path to the atomics folder. Default: C:\AtomicRedTeam\atomics

.PARAMETER ARTModulePath
    Path to the invoke-atomicredteam module folder. Default: C:\AtomicRedTeam\invoke-atomicredteam

.NOTES
    Run as Administrator on the target VM.
    See SETUP_INSTRUCTIONS.md for download steps.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$AtomicsPath = "C:\AtomicRedTeam\atomics",

    [Parameter()]
    [string]$ARTModulePath = "C:\AtomicRedTeam\invoke-atomicredteam"
)

$ErrorActionPreference = "Stop"

# -- Banner ------------------------------------------------------------------
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "  |       ART Automation Suite - Dependency Setup            |" -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

# -- Step 1: Validate PowerShell Version -------------------------------------
Write-Host "[1/5] Checking PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -lt 5) {
    Write-Error "PowerShell 5.1 or later is required. Current version: $psVersion"
    exit 1
}
Write-Host "  [OK] PowerShell $psVersion" -ForegroundColor Green

# -- Step 2: Check Execution Policy ------------------------------------------
Write-Host "[2/5] Checking execution policy..." -ForegroundColor Yellow
$policy = Get-ExecutionPolicy
if ($policy -eq "Restricted") {
    Write-Host "  [WARN] Policy is 'Restricted'. Setting to Bypass for this process..." -ForegroundColor DarkYellow
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    Write-Host "  [OK] Execution policy set to Bypass (process scope)" -ForegroundColor Green
} else {
    Write-Host "  [OK] Execution policy: $policy" -ForegroundColor Green
}

# -- Step 3: Validate ART Module Folder --------------------------------------
Write-Host "[3/5] Checking Invoke-AtomicRedTeam module..." -ForegroundColor Yellow

if (-not (Test-Path $ARTModulePath)) {
    Write-Host ""
    Write-Host "  [ERROR] Module folder not found at: $ARTModulePath" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please download Invoke-AtomicRedTeam first:" -ForegroundColor Yellow
    Write-Host "    1. Go to https://github.com/redcanaryco/invoke-atomicredteam" -ForegroundColor Gray
    Write-Host "    2. Click Code > Download ZIP" -ForegroundColor Gray
    Write-Host "    3. Extract and copy the folder to: $ARTModulePath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Or specify a custom path:" -ForegroundColor Yellow
    Write-Host "    .\Install-ARTDependencies.ps1 -ARTModulePath 'D:\path\to\invoke-atomicredteam'" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Install powershell-yaml (required dependency for invoke-atomicredteam)
$yamlModule = Get-Module -ListAvailable -Name "powershell-yaml" -ErrorAction SilentlyContinue
if (-not $yamlModule) {
    Write-Host "  Installing powershell-yaml (required dependency)..." -ForegroundColor Gray
    Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber
    Write-Host "  [OK] powershell-yaml installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] powershell-yaml already installed (v$($yamlModule.Version))" -ForegroundColor Green
}

# Import the module from local path
Import-Module $ARTModulePath -Force
Write-Host "  [OK] Invoke-AtomicRedTeam loaded from $ARTModulePath" -ForegroundColor Green

# -- Step 4: Validate Atomics Folder -----------------------------------------
Write-Host "[4/5] Checking atomics folder..." -ForegroundColor Yellow

if (-not (Test-Path $AtomicsPath)) {
    Write-Host ""
    Write-Host "  [ERROR] Atomics folder not found at: $AtomicsPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please download the atomics:" -ForegroundColor Yellow
    Write-Host "    1. Go to https://github.com/redcanaryco/atomic-red-team" -ForegroundColor Gray
    Write-Host "    2. Click Code > Download ZIP" -ForegroundColor Gray
    Write-Host "    3. Extract and copy the 'atomics' folder to: $AtomicsPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Or specify a custom path:" -ForegroundColor Yellow
    Write-Host "    .\Install-ARTDependencies.ps1 -AtomicsPath 'D:\path\to\atomics'" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

$atomicCount = (Get-ChildItem -Path $AtomicsPath -Directory | Where-Object { $_.Name -match "^T\d+" }).Count
Write-Host "  [OK] Found $atomicCount technique folders in $AtomicsPath" -ForegroundColor Green

# -- Step 5: Install ImportExcel Module --------------------------------------
Write-Host "[5/5] Installing ImportExcel module..." -ForegroundColor Yellow

# Ensure modules directory exists
$modDir = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Modules"
if (-not (Test-Path $modDir)) {
    New-Item -Path $modDir -ItemType Directory -Force | Out-Null
}

# Ensure NuGet provider
$nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if (-not $nuget -or $nuget.Version -lt [Version]"2.8.5.201") {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

$excelModule = Get-Module -ListAvailable -Name "ImportExcel" -ErrorAction SilentlyContinue
if ($excelModule) {
    Write-Host "  [OK] ImportExcel already installed (v$($excelModule.Version))" -ForegroundColor Green
} else {
    Write-Host "  Installing ImportExcel (no Office required)..." -ForegroundColor Gray
    Install-Module -Name ImportExcel -Scope AllUsers -Force -AllowClobber
    Write-Host "  [OK] ImportExcel installed" -ForegroundColor Green
}

# -- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "  |              [OK] Setup Complete!                        |" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Module:  Invoke-AtomicRedTeam loaded" -ForegroundColor White
Write-Host "  Atomics: $atomicCount techniques at $AtomicsPath" -ForegroundColor White
Write-Host "  Excel:   ImportExcel ready" -ForegroundColor White
Write-Host ""
Write-Host "  Next Steps:" -ForegroundColor Yellow
Write-Host "    1. Build catalog:  .\Get-ARTTechniques.ps1" -ForegroundColor Gray
Write-Host "    2. Run attacks:    .\Invoke-ARTAutomation.ps1 -TechniqueIds 'T1016'" -ForegroundColor Gray
Write-Host "    3. View dashboard: Open ..\dashboard\index.html in browser" -ForegroundColor Gray
Write-Host ""
