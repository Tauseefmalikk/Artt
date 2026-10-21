<#
.SYNOPSIS
    Hardcoded ART re-test runner.
    Edit the $TestPlan hashtable below to set which techniques and test numbers to re-run,
    then execute this script. That is all.

.DESCRIPTION
    Calls Invoke-ARTAutomation.ps1 for each technique in the $TestPlan,
    passing exactly the test numbers you specify.
    No JSON, no Excel - just edit and run.

.EXAMPLE
    .\Invoke-ARTRetest.ps1
    .\Invoke-ARTRetest.ps1 -DryRun
    .\Invoke-ARTRetest.ps1 -AutoCleanup:$false -DelayBetweenTests 10
#>

[CmdletBinding()]
param(
    [Parameter()]
    [bool]$AutoCleanup = $true,

    [Parameter()]
    [int]$DelayBetweenTests = 10,

    [Parameter()]
    [Parameter()]
    [string]$OutputDir = (Join-Path $PSScriptRoot "..\results"),

    [Parameter()]
    [string]$AtomicsPath = "",

    [Parameter()]
    [string]$ARTModulePath = "",

    [Parameter()]
    [switch]$SkipPrereqCheck,

    [Parameter()]
    [bool]$ExportExcel = $true,

    [Parameter()]
    [switch]$DryRun
)

# ==============================================================================
# EDIT THIS SECTION — Add your techniques and test numbers to re-run
#
# Format:
#   "TechniqueID" = @(test_number, test_number, ...)
#
# Use @() with no numbers to run ALL tests for that technique.
#
# Examples:
#   "T1059.001" = @(1, 2)       -> runs test 1 and test 2 only
#   "T1016"     = @(1)          -> runs test 1 only
#   "T1082"     = @()           -> runs ALL tests
# ==============================================================================
$TestPlan = [ordered]@{
    "T1059.003" = @(1, 2, 3)
    "T1059.005" = @(1, 3)
    "T1059.007" = @(1, 2)
    "T1218"     = @(13, 14, 15, 16)
    "T1218.011" = @(14, 15, 16)
    "T1105"     = @(7, 8, 15, 17, 18, 23, 26, 28, 29, 30)
    "T1218.010" = @(3, 4, 5)
    "T1218.007" = @(1, 2, 3, 4, 6, 7, 8, 9, 10)
    "T1218.005" = @(1, 2, 3, 10)
    "T1218.004" = @(1, 2, 3, 4, 5, 6, 7)
    "T1218.001" = @(1, 8)
    "T1547.001" = @(1, 4, 5, 7)
    "T1546.003" = @(3)
    "T1204.002" = @(10, 13)
    "T1216"     = @(1, 2)
    "T1106"     = @(2, 3, 4)
    "T1548.002" = @(2, 3, 4, 5, 7, 9, 21, 23)
    "T1021.006" = @(2)
    "T1021.002" = @(2, 4)
    "T1021.003" = @(1, 2)
}
# ==============================================================================
# END OF EDIT SECTION
# ==============================================================================

$ErrorActionPreference = "Continue"
$ScriptDir  = $PSScriptRoot
$MainScript = Join-Path $ScriptDir "Invoke-ARTAutomation.ps1"

# -- Resolve Paths Dynamically -----------------------------------------------
# 1. Resolve ARTModulePath
if ([string]::IsNullOrWhiteSpace($ARTModulePath)) {
    $moduleCandidates = @(
        $env:ARTModulePath,
        (Join-Path $PSScriptRoot "..\..\invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "..\invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "..\..\..\invoke-atomicredteam"),
        (if ($env:HOME) { Join-Path $env:HOME "AtomicRedTeam/invoke-atomicredteam" }),
        (if ($env:HOMEDRIVE) { Join-Path $env:HOMEDRIVE "AtomicRedTeam\invoke-atomicredteam" }),
        "C:\AtomicRedTeam\invoke-atomicredteam"
    )
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
        (Join-Path $PSScriptRoot "..\..\..\atomics"),
        (if ($env:HOME) { Join-Path $env:HOME "AtomicRedTeam/atomics" }),
        (if ($env:HOMEDRIVE) { Join-Path $env:HOMEDRIVE "AtomicRedTeam\atomics" }),
        (if ($env:USERPROFILE) { Join-Path $env:USERPROFILE "AtomicRedTeam\atomics" }),
        "C:\AtomicRedTeam\atomics"
    )
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

# Ensure invoke-atomicredteam module can resolve the atomics folder
$env:PathToAtomicsFolder = $AtomicsPath
$PathToAtomicsFolder = $AtomicsPath
$global:PathToAtomicsFolder = $AtomicsPath
$PSDefaultParameterValues["Invoke-AtomicTest:PathToAtomicsFolder"] = $AtomicsPath
$PSDefaultParameterValues["Get-AtomicTechnique:PathToAtomicsFolder"] = $AtomicsPath

# Banner
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Magenta
Write-Host "  |       ART Re-Test Runner - Hardcoded Technique Replay    |" -ForegroundColor Magenta
Write-Host "  ============================================================" -ForegroundColor Magenta
Write-Host ""

# Validate main script
if (-not (Test-Path $MainScript)) {
    Write-Error "Invoke-ARTAutomation.ps1 not found at: $MainScript"
    exit 1
}

# Print plan
$totalPlanned = 0
Write-Host "  -- Test Plan ---------------------------------------------------" -ForegroundColor Yellow
Write-Host ("  {0,-18} {1}" -f "Technique ID", "Test Numbers") -ForegroundColor White
Write-Host ("  {0,-18} {1}" -f "------------------", "--------------------") -ForegroundColor DarkGray

foreach ($tid in $TestPlan.Keys) {
    $nums = $TestPlan[$tid]
    if ($nums.Count -eq 0) {
        Write-Host ("  {0,-18} ALL tests" -f $tid) -ForegroundColor Gray
    } else {
        Write-Host ("  {0,-18} #{1}" -f $tid, ($nums -join ", ")) -ForegroundColor Gray
        $totalPlanned += $nums.Count
    }
}

Write-Host ""
Write-Host "  Techniques : $($TestPlan.Count)" -ForegroundColor Cyan
Write-Host "  Auto Cleanup    : $AutoCleanup" -ForegroundColor Gray
Write-Host "  Delay (s)       : $DelayBetweenTests" -ForegroundColor Gray
Write-Host "  Dry Run         : $($DryRun.IsPresent)" -ForegroundColor Gray
Write-Host ""

if ($DryRun) {
    Write-Host "  [DRY RUN] Nothing executed. Remove -DryRun to run for real." -ForegroundColor Yellow
    exit 0
}

# Safety confirmation
Write-Host "  [!] This will run LIVE attack simulations on this machine." -ForegroundColor Red
$confirm = Read-Host "  Type YES to proceed, anything else to cancel"
if ($confirm -ne "YES") {
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit 0
}

# Execute Test Plan in a single unified session
Write-Host ""
$retestStart = Get-Date

$splatParams = @{
    TestPlan          = $TestPlan
    AutoCleanup       = $AutoCleanup
    DelayBetweenTests = $DelayBetweenTests
    OutputDir         = $OutputDir
    AtomicsPath       = $AtomicsPath
    ARTModulePath     = $ARTModulePath
    ExportExcel       = $ExportExcel
}

if ($SkipPrereqCheck) {
    $splatParams["SkipPrereqCheck"] = $true
}

try {
    & $MainScript @splatParams
}
catch {
    Write-Warning "  [ERROR] Execution failed: $_"
}

# Summary
$retestDuration = [math]::Round(((Get-Date) - $retestStart).TotalMinutes, 2)

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "  |            [OK] Re-Test Run Complete                     |" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Techniques run  : $techCount" -ForegroundColor Gray
Write-Host "  Duration        : $retestDuration minutes" -ForegroundColor Gray
Write-Host "  Results saved to: $OutputDir" -ForegroundColor Gray
Write-Host ""
