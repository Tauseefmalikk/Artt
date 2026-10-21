<#
.SYNOPSIS
    1-Click Master Runner for Atomic Red Team Automation Suite.

.DESCRIPTION
    Fully automated end-to-end execution for clients and security teams:
    1. Checks Administrator elevation (elevates automatically if launched via RUN_SIMULATION.bat).
    2. Automatically installs missing dependencies (NuGet, powershell-yaml, ImportExcel).
    3. Automatically downloads and extracts the Atomic Red Team 'atomics' library if not present.
    4. Automatically builds the technique catalog for the SOC dashboard.
    5. Reads the test plan (test_plan.json) and executes all attacks in a single unified session.
    6. Produces a single unified Excel report and JSON file in the 'results' folder.
    7. Automatically opens the results folder in Windows Explorer upon completion.

.PARAMETER TestPlanFile
    Path to custom test plan JSON file. Default: auto-detected test_plan.json.

.PARAMETER NonInteractive
    If specified, runs without pausing at safety prompts (ideal for automated headless runs).
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TestPlanFile = "",

    [Parameter()]
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

# Ensure TLS 1.2 for all downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -- Banner ------------------------------------------------------------------
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "  |       Atomic Red Team - 1-Click Simulation Runner        |" -ForegroundColor Cyan
Write-Host "  |         Fully Automated Assessment & Unified Report       |" -ForegroundColor Yellow
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

# -- Step 1: Administrator / Root Check -------------------------------------
Write-Host "[1/6] Checking Administrator / Root privileges..." -ForegroundColor Yellow

$isUnix = ($null -ne (Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue) -and $IsMacOS) -or ($null -ne (Get-Variable -Name IsLinux -ErrorAction SilentlyContinue) -and $IsLinux)

if ($isUnix) {
    # Check if running as root on macOS/Linux
    $isAdmin = $false
    try {
        $isAdmin = ([System.Environment]::UserName -eq "root") -or ((id -u 2>$null) -eq 0)
    } catch {
        $isAdmin = ([System.Environment]::UserName -eq "root")
    }

    if (-not $isAdmin) {
        Write-Host "  [WARN] Not running with root privileges (sudo)!" -ForegroundColor DarkYellow
        Write-Host "  Please re-run this simulation using sudo:" -ForegroundColor Yellow
        Write-Host "    sudo pwsh `"$PSCommandPath`"" -ForegroundColor Cyan
        Write-Error "Root privileges (sudo) are required to simulate security attacks and inspect system events."
        exit 1
    }
} else {
    # Windows Administrator Check & Auto-Elevation
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "  [WARN] Not running as Administrator!" -ForegroundColor DarkYellow
        Write-Host "  Requesting elevated permissions..." -ForegroundColor Yellow
        try {
            $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            if ($TestPlanFile) { $arguments += " -TestPlanFile `"$TestPlanFile`"" }
            if ($NonInteractive) { $arguments += " -NonInteractive" }
            Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
            exit 0
        } catch {
            Write-Error "Administrator privileges are required to simulate security attacks and inspect system events."
            exit 1
        }
    }
}
Write-Host "  [OK] Elevated privileges confirmed." -ForegroundColor Green

# -- Step 2: Resolve Project Paths ------------------------------------------
Write-Host "[2/6] Detecting project structure and module paths..." -ForegroundColor Yellow

$scriptRoot = $PSScriptRoot

# Locate invoke-atomicredteam module
$moduleCandidates = @(
    (Join-Path $scriptRoot "..\..\invoke-atomicredteam"),
    (Join-Path $scriptRoot "..\invoke-atomicredteam"),
    (Join-Path $scriptRoot "invoke-atomicredteam"),
    (Join-Path $scriptRoot "..\..\..\invoke-atomicredteam")
)
if ($env:HOME) { $moduleCandidates += (Join-Path $env:HOME "AtomicRedTeam/invoke-atomicredteam") }
if ($env:HOMEDRIVE) { $moduleCandidates += (Join-Path $env:HOMEDRIVE "AtomicRedTeam\invoke-atomicredteam") }
$moduleCandidates += "C:\AtomicRedTeam\invoke-atomicredteam"

$artModulePath = $null
foreach ($cand in $moduleCandidates) {
    if ($cand -and (Test-Path $cand)) {
        $artModulePath = (Resolve-Path $cand).Path
        break
    }
}
if (-not $artModulePath) {
    Write-Error "Could not locate invoke-atomicredteam module directory. Please ensure it is inside the project folder."
    exit 1
}
Write-Host "  [OK] Invoke-AtomicRedTeam module found at: $artModulePath" -ForegroundColor Green

# Determine target atomics path
$atomicsCandidates = @(
    $env:PathToAtomicsFolder,
    (Join-Path $scriptRoot "..\..\atomics"),
    (Join-Path $scriptRoot "..\atomics"),
    (Join-Path $scriptRoot "atomics"),
    (Join-Path $scriptRoot "..\..\..\atomics")
)
if ($env:HOME) { $atomicsCandidates += (Join-Path $env:HOME "AtomicRedTeam/atomics") }
if ($env:HOMEDRIVE) { $atomicsCandidates += (Join-Path $env:HOMEDRIVE "AtomicRedTeam\atomics") }
if ($env:USERPROFILE) { $atomicsCandidates += (Join-Path $env:USERPROFILE "AtomicRedTeam\atomics") }
$atomicsCandidates += "C:\AtomicRedTeam\atomics"

$atomicsPath = $null
foreach ($cand in $atomicsCandidates) {
    if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand)) {
        $atomicsPath = (Resolve-Path $cand).Path
        break
    }
}

# If atomics path doesn't exist yet, choose the standard project location
if (-not $atomicsPath) {
    $parentDir = Split-Path (Split-Path $scriptRoot -Parent) -Parent
    if ($parentDir -and (Test-Path $parentDir)) {
        $atomicsPath = Join-Path $parentDir "atomics"
    } else {
        $atomicsPath = Join-Path $scriptRoot "..\..\atomics"
    }
}

# Resolve Output Directory
$outputDir = (Resolve-Path (Join-Path $scriptRoot "..\results") -ErrorAction SilentlyContinue)
if (-not $outputDir) {
    $outputDir = Join-Path $scriptRoot "..\results"
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
} else {
    $outputDir = $outputDir.Path
}

# Resolve Test Plan File
if (-not $TestPlanFile) {
    $planCandidates = @(
        (Join-Path $scriptRoot "..\..\test_plan.json"),
        (Join-Path $scriptRoot "..\test_plan.json"),
        (Join-Path $scriptRoot "test_plan.json"),
        (Join-Path $scriptRoot "..\..\..\test_plan.json")
    )
    foreach ($cand in $planCandidates) {
        if (Test-Path $cand) {
            $TestPlanFile = (Resolve-Path $cand).Path
            break
        }
    }
}

# -- Step 3: Install & Verify PowerShell Dependencies ------------------------
Write-Host "[3/6] Verifying PowerShell dependencies..." -ForegroundColor Yellow

if (-not $isUnix) {
    # Ensure PackageProvider NuGet (Windows PowerShell only)
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nuget -or $nuget.Version -lt [Version]"2.8.5.201") {
        Write-Host "  Installing NuGet Package Provider..." -ForegroundColor Gray
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

# Ensure powershell-yaml
$yamlModule = Get-Module -ListAvailable -Name "powershell-yaml" -ErrorAction SilentlyContinue
if (-not $yamlModule) {
    Write-Host "  Installing required module: powershell-yaml..." -ForegroundColor Gray
    Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber | Out-Null
    Write-Host "  [OK] powershell-yaml installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] powershell-yaml ready" -ForegroundColor Green
}

# Ensure ImportExcel
$excelModule = Get-Module -ListAvailable -Name "ImportExcel" -ErrorAction SilentlyContinue
if (-not $excelModule) {
    Write-Host "  Installing required module: ImportExcel..." -ForegroundColor Gray
    Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber | Out-Null
    Write-Host "  [OK] ImportExcel installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] ImportExcel ready" -ForegroundColor Green
}

# Load invoke-atomicredteam
Import-Module $artModulePath -Force -ErrorAction Stop
Write-Host "  [OK] Invoke-AtomicRedTeam loaded." -ForegroundColor Green

# -- Step 4: Ensure Atomics Definitions are Present --------------------------
Write-Host "[4/6] Checking Atomic Red Team attack definitions..." -ForegroundColor Yellow

$needsDownload = $true
if (Test-Path $atomicsPath) {
    $techFolderCount = (Get-ChildItem -Path $atomicsPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^T\d+" }).Count
    if ($techFolderCount -gt 0) {
        $needsDownload = $false
        Write-Host "  [OK] Found $techFolderCount technique definitions in: $atomicsPath" -ForegroundColor Green
    }
}

if ($needsDownload) {
    Write-Host "  [i] Atomics folder not found locally." -ForegroundColor Yellow
    Write-Host "  [+] Downloading Atomic Red Team attack library from GitHub..." -ForegroundColor Cyan
    Write-Host "      Target destination: $atomicsPath" -ForegroundColor DarkGray
    
    $parentAtomics = Split-Path $atomicsPath -Parent
    if (-not (Test-Path $parentAtomics)) {
        New-Item -Path $parentAtomics -ItemType Directory -Force | Out-Null
    }

    $downloadSuccess = $false
    # Try using bundled install-atomicsfolder.ps1
    $installerScript = Join-Path $artModulePath "install-atomicsfolder.ps1"
    if (Test-Path $installerScript) {
        try {
            . $installerScript
            Install-AtomicsFolder -InstallPath $parentAtomics
            if (Test-Path $atomicsPath) {
                $downloadSuccess = $true
            }
        } catch {
            Write-Host "  [WARN] Default installer encountered: $_" -ForegroundColor DarkYellow
        }
    }

    # Fallback direct download if needed
    if (-not $downloadSuccess -or -not (Test-Path $atomicsPath)) {
        Write-Host "  Downloading via direct GitHub zip archive..." -ForegroundColor Gray
        $zipUrl = "https://github.com/redcanaryco/atomic-red-team/archive/master.zip"
        $tempBase = [System.IO.Path]::GetTempPath()
        $tmpZip = Join-Path $tempBase "atomic-red-team-master.zip"
        $tmpExtract = Join-Path $tempBase "atomic-red-team-extract-$([guid]::NewGuid().ToString('N'))"
        
        try {
            Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing
            Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpExtract -Force
            $extractedAtomics = Join-Path (Join-Path $tmpExtract "atomic-red-team-master") "atomics"
            if (Test-Path $extractedAtomics) {
                Copy-Item -Path $extractedAtomics -Destination $atomicsPath -Recurse -Force
                $downloadSuccess = $true
            }
        } finally {
            Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path $atomicsPath) {
        $techFolderCount = (Get-ChildItem -Path $atomicsPath -Directory | Where-Object { $_.Name -match "^T\d+" }).Count
        Write-Host "  [OK] Successfully downloaded $techFolderCount techniques to $atomicsPath" -ForegroundColor Green
    } else {
        Write-Error "Failed to download atomics library. Please check internet connection."
        exit 1
    }
}

# Set environment and session variables
$env:PathToAtomicsFolder = $atomicsPath
$PathToAtomicsFolder = $atomicsPath
$global:PathToAtomicsFolder = $atomicsPath
$PSDefaultParameterValues["Invoke-AtomicTest:PathToAtomicsFolder"] = $atomicsPath
$PSDefaultParameterValues["Get-AtomicTechnique:PathToAtomicsFolder"] = $atomicsPath

# -- Step 5: Build Catalog for Dashboard -------------------------------------
Write-Host "[5/6] Building / updating technique catalog..." -ForegroundColor Yellow
$catalogScript = Join-Path $scriptRoot "Get-ARTTechniques.ps1"
if (Test-Path $catalogScript) {
    try {
        & $catalogScript -AtomicsPath $atomicsPath -ARTModulePath $artModulePath | Out-Null
        Write-Host "  [OK] SOC Dashboard technique catalog updated." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Catalog builder warning: $_" -ForegroundColor DarkYellow
    }
}

# -- Step 6: Execute Test Plan in Single Unified Session --------------------
Write-Host "[6/6] Executing attack simulation plan..." -ForegroundColor Yellow

# Verify test plan file
if (-not $TestPlanFile -or -not (Test-Path $TestPlanFile)) {
    Write-Host "  Creating default test_plan.json..." -ForegroundColor Gray
    $TestPlanFile = Join-Path $scriptRoot "..\test_plan.json"
    $defaultPlan = [ordered]@{
        "Description"       = "Atomic Red Team - Multi-Platform Security Assessment Plan"
        "AutoCleanup"       = $true
        "DelayBetweenTests" = 10
        "SkipPrereqCheck"   = $false
        "Platforms"         = [ordered]@{
            "windows" = [ordered]@{
                "T1082"     = @(34)
                "T1057"     = @(2, 3, 4, 6)
                "T1007"     = @(1, 2, 4, 6, 7)
                "T1033"     = @(4, 5, 6, 7)
                "T1049"     = @(1, 2, 3)
                "T1059.001" = @(10, 17)
                "T1105"     = @(10)
                "T1218.005" = @(1)
                "T1218.011" = @(16)
                "T1548.002" = @(7)
                "T1547.001" = @(1, 3, 4, 6)
                "T1047"     = @(7)
                "T1070.004" = @(4, 6, 10)
                "T1005"     = @(1)
                "T1074.001" = @(1, 3)
                "T1036"     = @(1)
                "T1036.002" = @(1)
                "T1036.003" = @(1)
                "T1036.004" = @(1)
                "T1036.007" = @(1)
                "T1036.005" = @(2, 3)
                "T1070.006" = @(8)
                "T1112"     = @(1)
                "T1041"     = @(1)
            }
            "macos" = [ordered]@{
                "T1082"     = @(1, 2)
                "T1016"     = @(1)
                "T1033"     = @(1)
                "T1059.002" = @(1, 2)
                "T1059.004" = @(1, 2)
            }
        }
        "Tests"             = [ordered]@{
            "T1082"     = @(34)
            "T1057"     = @(2, 3, 4, 6)
            "T1007"     = @(1, 2, 4, 6, 7)
            "T1033"     = @(4, 5, 6, 7)
            "T1049"     = @(1, 2, 3)
            "T1059.001" = @(10, 17)
            "T1105"     = @(10)
            "T1218.005" = @(1)
            "T1218.011" = @(16)
            "T1548.002" = @(7)
            "T1547.001" = @(1, 3, 4, 6)
            "T1047"     = @(7)
            "T1070.004" = @(4, 6, 10)
            "T1005"     = @(1)
            "T1074.001" = @(1, 3)
            "T1036"     = @(1)
            "T1036.002" = @(1)
            "T1036.003" = @(1)
            "T1036.004" = @(1)
            "T1036.007" = @(1)
            "T1036.005" = @(2, 3)
            "T1070.006" = @(8)
            "T1112"     = @(1)
            "T1041"     = @(1)
        }
    }
    $defaultPlan | ConvertTo-Json -Depth 5 | Out-File -FilePath $TestPlanFile -Encoding UTF8
}

Write-Host "  Using Test Plan: $TestPlanFile" -ForegroundColor Cyan

# Main execution via Invoke-ARTAutomation
$automationScript = Join-Path $scriptRoot "Invoke-ARTAutomation.ps1"
if (-not (Test-Path $automationScript)) {
    Write-Error "Could not locate Invoke-ARTAutomation.ps1 at: $automationScript"
    exit 1
}

# Run the unified attack session
& $automationScript -TestPlanFile $TestPlanFile -AtomicsPath $atomicsPath -ARTModulePath $artModulePath -OutputDir $outputDir

# -- Completion & Presentation -----------------------------------------------
$unifiedExcel = Join-Path $outputDir "ART_Results.xlsx"
$unifiedJson  = Join-Path $outputDir "ART_Results.json"
$dashboardHtml = Resolve-Path (Join-Path $scriptRoot "..\dashboard\index.html") -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "  |                 SIMULATION COMPLETE!                     |" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Unified Report Files Ready:" -ForegroundColor White
if (Test-Path $unifiedExcel) {
    Write-Host "    [Excel Spreadsheet] $unifiedExcel" -ForegroundColor Green
}
if (Test-Path $unifiedJson) {
    Write-Host "    [JSON Summary File] $unifiedJson" -ForegroundColor Green
}
if ($dashboardHtml) {
    Write-Host "    [SOC Dashboard HTML] $($dashboardHtml.Path)" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  Opening results folder..." -ForegroundColor Yellow

# Automatically open the results folder
try {
    if ($isUnix) {
        if ($null -ne (Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue) -and $IsMacOS) {
            Start-Process "open" -ArgumentList "`"$outputDir`""
        } elseif (Get-Command xdg-open -ErrorAction SilentlyContinue) {
            Start-Process "xdg-open" -ArgumentList "`"$outputDir`""
        }
    } else {
        Invoke-Item $outputDir
    }
} catch {
    # Non-blocking if running headless
}

Write-Host "  [OK] Done." -ForegroundColor Green
Write-Host ""
