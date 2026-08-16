<#
.SYNOPSIS
    Generates a single-sheet Excel report from ART attack results JSON.

.DESCRIPTION
    Takes JSON results from Invoke-ARTAutomation and creates a simple,
    single-sheet Excel workbook with one row per test result.

    This is for manual re-export — the main automation script already
    writes Excel in real-time during execution.

.PARAMETER InputJson
    Path to the JSON results file from Invoke-ARTAutomation

.PARAMETER OutputDir
    Output directory for the Excel file. Default: ..\results

.PARAMETER OutputFile
    Specific output file name. Default: auto-generated with timestamp

.EXAMPLE
    .\Export-ARTReport.ps1 -InputJson "..\results\ART_Results_20250814.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputJson,

    [Parameter()]
    [string]$OutputDir = (Join-Path $PSScriptRoot "..\results"),

    [Parameter()]
    [string]$OutputFile
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "  ==========================================================" -ForegroundColor Cyan
Write-Host "  |        ART Excel Report Generator                      |" -ForegroundColor Cyan
Write-Host "  ==========================================================" -ForegroundColor Cyan
Write-Host ""

# Import modules
Import-Module ImportExcel -Force -ErrorAction Stop

# Validate input
if (-not (Test-Path $InputJson)) {
    Write-Error "Input file not found: $InputJson"
    exit 1
}

# Load JSON data
Write-Host "  Loading results from: $InputJson" -ForegroundColor Gray
$data = Get-Content $InputJson -Raw | ConvertFrom-Json
$session = $data.SessionInfo
$results = $data.Results

if (-not $results -or $results.Count -eq 0) {
    Write-Error "No results found in the JSON file."
    exit 1
}

Write-Host "  Found $($results.Count) test results" -ForegroundColor Gray

# Determine output path
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

if (-not $OutputFile) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputFile = "ART_Report_$timestamp.xlsx"
}

$excelPath = Join-Path $OutputDir $OutputFile

# Remove existing file to avoid conflicts
if (Test-Path $excelPath) {
    Remove-Item $excelPath -Force
}

# Helper: safely get technique ID as string
function Get-TechIdString($techId) {
    if ($techId -is [array]) { return $techId -join ", " }
    return [string]$techId
}

# ==============================================================================
# SINGLE SHEET: All Results
# ==============================================================================
Write-Host "  Creating Results sheet..." -ForegroundColor Yellow

$flatResults = $results | ForEach-Object {
    $techIdStr = Get-TechIdString $_.TechniqueID

    [PSCustomObject]@{
        "Technique ID"     = $techIdStr
        "Technique Name"   = $_.TechniqueName
        "Tactic"           = $_.Tactic
        "Test Name"        = $_.TestName
        "Test #"           = $_.TestNumber
        "Executor"         = $_.ExecutorType
        "Start Time"       = $_.StartTime
        "End Time"         = $_.EndTime
        "Duration (s)"     = $_.Duration
        "Status"           = $_.Status
        "Executed Command" = if ($_.ExecutedCommand.Length -gt 500) { $_.ExecutedCommand.Substring(0, 500) + "..." } else { $_.ExecutedCommand }
        "Command Output"   = if ($_.CommandOutput.Length -gt 500) { $_.CommandOutput.Substring(0, 500) + "..." } else { $_.CommandOutput }
        "Error Message"    = $_.ErrorMessage
        "Cleanup Command"  = $_.CleanupCommand
        "Cleanup Status"   = $_.CleanupStatus
        "Prerequisites"    = if ($_.PrereqsMet) { "Met" } else { "Not Met" }
        "Hostname"         = $_.Hostname
        "Username"         = $_.Username
    }
}

$flatResults | Export-Excel -Path $excelPath -WorksheetName "Results" `
    -AutoSize -BoldTopRow -FreezeTopRow -AutoFilter -TableStyle Medium2

# -- Done --------------------------------------------------------------------
Write-Host ""
Write-Host "  [OK] Excel report generated: $excelPath" -ForegroundColor Green
Write-Host "  Rows: $($results.Count) test results in a single sheet" -ForegroundColor Gray
Write-Host ""
