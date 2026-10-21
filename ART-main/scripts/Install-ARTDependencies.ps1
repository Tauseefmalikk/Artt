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
    Path to the atomics folder. Default: Auto-detected (e.g. ..\..\atomics or C:\AtomicRedTeam\atomics)

.PARAMETER ARTModulePath
    Path to the invoke-atomicredteam module folder. Default: Auto-detected (e.g. ..\..\invoke-atomicredteam or C:\AtomicRedTeam\invoke-atomicredteam)

.PARAMETER DownloadAtomics
    Switch to automatically download and extract the atomics folder from GitHub.

.NOTES
    Run as Administrator on the target VM.
    See SETUP_INSTRUCTIONS.md for download steps.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$AtomicsPath = "",

    [Parameter()]
    [string]$ARTModulePath = "",

    [Parameter()]
    [switch]$DownloadAtomics
)

$ErrorActionPreference = "Stop"

# -- Resolve Paths Dynamically -----------------------------------------------
# 1. Resolve ARTModulePath
if ([string]::IsNullOrWhiteSpace($ARTModulePath)) {
    $moduleCandidates = @(
        $env:ARTModulePath,
        (Join-Path $PSScriptRoot "..\..\invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "..\invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "..\..\..\invoke-atomicredteam")
    )
    if ($env:HOME) { $moduleCandidates += (Join-Path $env:HOME "AtomicRedTeam/invoke-atomicredteam") }
    if ($env:HOMEDRIVE) { $moduleCandidates += (Join-Path $env:HOMEDRIVE "AtomicRedTeam\invoke-atomicredteam") }
    $moduleCandidates += "C:\AtomicRedTeam\invoke-atomicredteam"

    foreach ($cand in $moduleCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand)) {
            $ARTModulePath = (Resolve-Path $cand).Path
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($ARTModulePath)) {
        $ARTModulePath = (Join-Path $PSScriptRoot "..\..\invoke-atomicredteam")
    }
} elseif (Test-Path $ARTModulePath) {
    $ARTModulePath = (Resolve-Path $ARTModulePath).Path
}

# 2. Resolve AtomicsPath
if ([string]::IsNullOrWhiteSpace($AtomicsPath)) {
    $atomicsCandidates = @(
        $env:PathToAtomicsFolder,
        (Join-Path $PSScriptRoot "..\..\atomics"),
        (Join-Path $PSScriptRoot "..\atomics"),
        (Join-Path $PSScriptRoot "atomics"),
        (Join-Path $PSScriptRoot "..\..\..\atomics")
    )
    if ($env:HOME) { $atomicsCandidates += (Join-Path $env:HOME "AtomicRedTeam/atomics") }
    if ($env:HOMEDRIVE) { $atomicsCandidates += (Join-Path $env:HOMEDRIVE "AtomicRedTeam\atomics") }
    if ($env:USERPROFILE) { $atomicsCandidates += (Join-Path $env:USERPROFILE "AtomicRedTeam\atomics") }
    $atomicsCandidates += "C:\AtomicRedTeam\atomics"

    foreach ($cand in $atomicsCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand)) {
            $AtomicsPath = (Resolve-Path $cand).Path
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($AtomicsPath)) {
        $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        if ($projectRoot -and (Test-Path $projectRoot)) {
            $AtomicsPath = Join-Path $projectRoot "atomics"
        } else {
            $AtomicsPath = Join-Path $PSScriptRoot "..\..\atomics"
        }
    }
} elseif (Test-Path $AtomicsPath) {
    $AtomicsPath = (Resolve-Path $AtomicsPath).Path
}

# Set environment and session variables for invoke-atomicredteam
$env:PathToAtomicsFolder = $AtomicsPath
$PathToAtomicsFolder = $AtomicsPath
$global:PathToAtomicsFolder = $AtomicsPath
$PSDefaultParameterValues["Invoke-AtomicTest:PathToAtomicsFolder"] = $AtomicsPath

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
    Write-Host "  Please ensure invoke-atomicredteam is placed in your project or at: $ARTModulePath" -ForegroundColor Yellow
    Write-Host "    Or specify custom path: .\Install-ARTDependencies.ps1 -ARTModulePath 'path\to\invoke-atomicredteam'" -ForegroundColor Gray
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

# Import the module from resolved local path
Import-Module $ARTModulePath -Force
Write-Host "  [OK] Invoke-AtomicRedTeam loaded from $ARTModulePath" -ForegroundColor Green

# -- Step 4: Validate Atomics Folder -----------------------------------------
Write-Host "[4/5] Checking atomics folder..." -ForegroundColor Yellow

if ($DownloadAtomics) {
    Write-Host "  [-DownloadAtomics specified] Downloading atomics from GitHub..." -ForegroundColor Cyan
    $installerScript = Join-Path $ARTModulePath "install-atomicsfolder.ps1"
    if (Test-Path $installerScript) {
        . $installerScript
        $parentFolder = Split-Path $AtomicsPath -Parent
        if (-not (Test-Path $parentFolder)) {
            New-Item -Path $parentFolder -ItemType Directory -Force | Out-Null
        }
        Install-AtomicsFolder -InstallPath $parentFolder
        if (Test-Path $AtomicsPath) {
            Write-Host "  [OK] Successfully downloaded atomics folder to: $AtomicsPath" -ForegroundColor Green
        }
    } else {
        Write-Host "  [WARN] Could not find installer script at: $installerScript" -ForegroundColor DarkYellow
    }
}

$atomicCount = 0
if (-not (Test-Path $AtomicsPath)) {
    Write-Host ""
    Write-Host "  [WARN] Atomics folder not found at: $AtomicsPath" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "  You can automatically download atomics using:" -ForegroundColor Yellow
    Write-Host "    .\Install-ARTDependencies.ps1 -DownloadAtomics" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or manually download:" -ForegroundColor Yellow
    Write-Host "    1. Go to https://github.com/redcanaryco/atomic-red-team" -ForegroundColor Gray
    Write-Host "    2. Click Code > Download ZIP" -ForegroundColor Gray
    Write-Host "    3. Extract the 'atomics' folder to: $AtomicsPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Or pass a custom path when running attacks:" -ForegroundColor Yellow
    Write-Host "    .\Invoke-ARTAutomation.ps1 -AtomicsPath 'D:\path\to\atomics'" -ForegroundColor Gray
    Write-Host ""
} else {
    $atomicCount = (Get-ChildItem -Path $AtomicsPath -Directory | Where-Object { $_.Name -match "^T\d+" }).Count
    Write-Host "  [OK] Found $atomicCount technique folders in $AtomicsPath" -ForegroundColor Green
}

# -- Step 5: Install ImportExcel Module --------------------------------------
Write-Host "[5/5] Installing ImportExcel module..." -ForegroundColor Yellow

# Ensure modules directory exists
$userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
if ($userHome) {
    $isUnix = ($null -ne (Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue) -and $IsMacOS) -or ($null -ne (Get-Variable -Name IsLinux -ErrorAction SilentlyContinue) -and $IsLinux)
    $modDir = if ($isUnix) {
        Join-Path $userHome ".local/share/powershell/Modules"
    } else {
        Join-Path $userHome "Documents\WindowsPowerShell\Modules"
    }
    if (-not (Test-Path $modDir)) {
        New-Item -Path $modDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
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
    Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
    Write-Host "  [OK] ImportExcel installed" -ForegroundColor Green
}

# -- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "  |              [OK] Setup Complete!                        |" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Module:  Invoke-AtomicRedTeam loaded from $ARTModulePath" -ForegroundColor White
if (Test-Path $AtomicsPath) {
    Write-Host "  Atomics: $atomicCount techniques at $AtomicsPath" -ForegroundColor White
} else {
    Write-Host "  Atomics: [Pending download] Path: $AtomicsPath" -ForegroundColor DarkYellow
}
Write-Host "  Excel:   ImportExcel ready" -ForegroundColor White
Write-Host ""
Write-Host "  Next Steps:" -ForegroundColor Yellow
Write-Host "    1. Build catalog:  .\Get-ARTTechniques.ps1" -ForegroundColor Gray
Write-Host "    2. Run attacks:    .\Invoke-ARTAutomation.ps1 -TechniqueIds 'T1016'" -ForegroundColor Gray
Write-Host "    3. View dashboard: Open ..\dashboard\index.html in browser" -ForegroundColor Gray
Write-Host ""
