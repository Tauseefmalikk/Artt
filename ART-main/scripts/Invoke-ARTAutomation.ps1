<#
.SYNOPSIS
    Core ART attack automation engine with full telemetry capture.

.DESCRIPTION
    Runs Atomic Red Team tests with comprehensive logging of:
    - Start/end timestamps, duration
    - Actual commands executed
    - Command output (stdout/stderr)
    - Cleanup commands and status
    - Prerequisites check results
    - Host and user context

    Results are saved as JSON (for dashboard) and as a real-time Excel file.
    The Excel is updated after EVERY test — if you stop mid-run (Ctrl+C),
    you still keep all results captured so far.

.PARAMETER TechniqueIds
    Comma-separated list of MITRE ATT&CK technique IDs (e.g., "T1059.001,T1003")

.PARAMETER Tactic
    Run all techniques in a specific tactic category (e.g., "Discovery", "Credential Access")

.PARAMETER RunAll
    Run every available technique (use with caution!)

.PARAMETER TestNumbers
    Specific test numbers to run within each technique (e.g., 1,2,3). Default: all.

.PARAMETER AutoCleanup
    Automatically run cleanup after each test (default: true)

.PARAMETER DelayBetweenTests
    Seconds to wait between tests, gives EDR time to process (default: 30)

.PARAMETER OutputDir
    Output directory for results. Default: ..\results

.PARAMETER AtomicsPath
    Path to the atomics folder. Default: Auto-detected (e.g. ..\..\atomics or C:\AtomicRedTeam\atomics)

.PARAMETER SkipPrereqCheck
    Skip prerequisite validation before running tests

.PARAMETER ExportExcel
    Automatically export results to Excel in real-time (default: true)

.PARAMETER ARTModulePath
    Path to invoke-atomicredteam module. Default: Auto-detected (e.g. ..\..\invoke-atomicredteam or C:\AtomicRedTeam\invoke-atomicredteam)

.EXAMPLE
    # Run specific techniques
    .\Invoke-ARTAutomation.ps1 -TechniqueIds "T1016,T1059.001"

    # Run all Discovery techniques
    .\Invoke-ARTAutomation.ps1 -Tactic "Discovery"

    # Run with custom delay and no cleanup
    .\Invoke-ARTAutomation.ps1 -TechniqueIds "T1003" -AutoCleanup:$false -DelayBetweenTests 60
#>

[CmdletBinding(DefaultParameterSetName = "ByTechnique")]
param(
    [Parameter(ParameterSetName = "ByTechnique", Mandatory = $true)]
    [string]$TechniqueIds,

    [Parameter(ParameterSetName = "ByTactic", Mandatory = $true)]
    [ValidateSet(
        "Reconnaissance", "Resource Development", "Initial Access", "Execution",
        "Persistence", "Privilege Escalation", "Defense Evasion", "Credential Access",
        "Discovery", "Lateral Movement", "Collection", "Command and Control",
        "Exfiltration", "Impact"
    )]
    [string]$Tactic,

    [Parameter(ParameterSetName = "RunAll", Mandatory = $true)]
    [switch]$RunAll,

    [Parameter(ParameterSetName = "PlanFile")]
    [string]$TestPlanFile,

    [Parameter(ParameterSetName = "PlanObject")]
    [hashtable]$TestPlan,

    [Parameter()]
    [int[]]$TestNumbers,

    [Parameter()]
    [bool]$AutoCleanup = $true,

    [Parameter()]
    [int]$DelayBetweenTests = 30,

    [Parameter()]
    [string]$OutputDir = (Join-Path $PSScriptRoot "..\results"),

    [Parameter()]
    [string]$AtomicsPath = "",

    [Parameter()]
    [switch]$SkipPrereqCheck,

    [Parameter()]
    [bool]$ExportExcel = $true,

    [Parameter()]
    [string]$ARTModulePath = ""
)

$ErrorActionPreference = "Continue"

# -- Resolve Paths Dynamically -----------------------------------------------
# 1. Resolve ARTModulePath
if ([string]::IsNullOrWhiteSpace($ARTModulePath)) {
    $moduleCandidates = @(
        $env:ARTModulePath,
        (Join-Path $PSScriptRoot "..\..\invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "..\invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "invoke-atomicredteam"),
        (Join-Path $PSScriptRoot "..\..\..\invoke-atomicredteam"),
        (Join-Path $env:HOMEDRIVE "AtomicRedTeam\invoke-atomicredteam"),
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
        (Join-Path $env:HOMEDRIVE "AtomicRedTeam\atomics"),
        (Join-Path $env:USERPROFILE "AtomicRedTeam\atomics"),
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

# -- Import Required Modules ------------------------------------------------
if (Test-Path $ARTModulePath) {
    Import-Module $ARTModulePath -Force -ErrorAction Stop
} else {
    Import-Module invoke-atomicredteam -Force -ErrorAction Stop
}

# Ensure invoke-atomicredteam resolves the correct atomics folder:
$env:PathToAtomicsFolder = $AtomicsPath
$PathToAtomicsFolder = $AtomicsPath
$global:PathToAtomicsFolder = $AtomicsPath
$PSDefaultParameterValues["Invoke-AtomicTest:PathToAtomicsFolder"] = $AtomicsPath
$PSDefaultParameterValues["Get-AtomicTechnique:PathToAtomicsFolder"] = $AtomicsPath

# Validate AtomicsPath exists before running attacks
if (-not (Test-Path $AtomicsPath)) {
    Write-Host ""
    Write-Host "  [ERROR] Atomics folder not found at: $AtomicsPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please specify the atomics folder location using -AtomicsPath, or run:" -ForegroundColor Yellow
    Write-Host "    .\Install-ARTDependencies.ps1 -DownloadAtomics" -ForegroundColor White
    Write-Host ""
    return
}
# -- Banner ------------------------------------------------------------------
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Red
Write-Host "  |       ART Automation Engine - Attack Runner              |" -ForegroundColor Red
Write-Host "  |              [!]  LIVE ATTACK SIMULATION  [!]            |" -ForegroundColor Yellow
Write-Host "  ============================================================" -ForegroundColor Red
Write-Host ""

# -- Tactic-to-Technique Mapping --------------------------------------------
$TacticMap = @{
    "Reconnaissance"          = @("T1595", "T1592", "T1589", "T1590", "T1591", "T1596", "T1593", "T1594", "T1597", "T1598")
    "Resource Development"    = @("T1583", "T1584", "T1585", "T1586", "T1587", "T1588", "T1608")
    "Initial Access"          = @("T1189", "T1190", "T1133", "T1200", "T1566", "T1091", "T1195", "T1199", "T1078")
    "Execution"               = @("T1059", "T1203", "T1559", "T1106", "T1053", "T1129", "T1072", "T1569", "T1204", "T1047")
    "Persistence"             = @("T1098", "T1197", "T1547", "T1037", "T1136", "T1543", "T1546", "T1133", "T1574", "T1525", "T1556", "T1137", "T1542", "T1053", "T1505", "T1205", "T1078")
    "Privilege Escalation"    = @("T1548", "T1134", "T1547", "T1037", "T1543", "T1484", "T1546", "T1068", "T1574", "T1055", "T1053", "T1078")
    "Defense Evasion"         = @("T1548", "T1134", "T1197", "T1140", "T1006", "T1484", "T1480", "T1211", "T1222", "T1564", "T1574", "T1562", "T1070", "T1202", "T1036", "T1556", "T1578", "T1112", "T1601", "T1599", "T1027", "T1542", "T1055", "T1207", "T1014", "T1218", "T1216", "T1553", "T1221", "T1205", "T1127", "T1535", "T1550", "T1078", "T1497", "T1600", "T1220")
    "Credential Access"       = @("T1110", "T1555", "T1212", "T1187", "T1606", "T1056", "T1557", "T1556", "T1111", "T1621", "T1040", "T1003", "T1528", "T1558", "T1539", "T1552")
    "Discovery"               = @("T1087", "T1010", "T1217", "T1580", "T1538", "T1526", "T1619", "T1613", "T1622", "T1482", "T1083", "T1615", "T1046", "T1135", "T1040", "T1201", "T1120", "T1069", "T1057", "T1012", "T1018", "T1518", "T1082", "T1614", "T1016", "T1049", "T1033", "T1007", "T1124", "T1497")
    "Lateral Movement"        = @("T1210", "T1534", "T1570", "T1563", "T1021", "T1091", "T1072", "T1080", "T1550")
    "Collection"              = @("T1557", "T1560", "T1123", "T1119", "T1185", "T1115", "T1530", "T1602", "T1213", "T1005", "T1039", "T1025", "T1074", "T1114", "T1056", "T1113", "T1125")
    "Command and Control"     = @("T1071", "T1092", "T1132", "T1001", "T1568", "T1573", "T1008", "T1105", "T1104", "T1095", "T1571", "T1572", "T1090", "T1219", "T1205", "T1102")
    "Exfiltration"            = @("T1020", "T1030", "T1048", "T1041", "T1011", "T1052", "T1567", "T1029", "T1537")
    "Impact"                  = @("T1531", "T1485", "T1486", "T1565", "T1491", "T1561", "T1499", "T1495", "T1490", "T1498", "T1496", "T1489", "T1529")
}

# FIX Bug #9: Return ALL matching tactics, not just the first one
function Get-TacticForTechnique($TechniqueId) {
    $baseId = $TechniqueId -replace '\..*$', ''
    $matchedTactics = @()
    foreach ($tactic in $TacticMap.Keys) {
        if ($TacticMap[$tactic] -contains $baseId) {
            $matchedTactics += $tactic
        }
    }
    if ($matchedTactics.Count -eq 0) { return "Unknown" }
    return ($matchedTactics -join ", ")
}

# -- Parse Techniques --------------------------------------------------------
$techniquesToRun = @()
$planTestMap = @{}

if ($TestPlanFile -or $TestPlan) {
    if ($TestPlanFile) {
        if (-not (Test-Path $TestPlanFile)) {
            Write-Error "Test plan file not found at: $TestPlanFile"
            exit 1
        }
        $rawPlan = Get-Content $TestPlanFile -Raw | ConvertFrom-Json
        $testsObj = if ($rawPlan.Tests) { $rawPlan.Tests } else { $rawPlan }
        foreach ($prop in $testsObj.PSObject.Properties) {
            $planTestMap[$prop.Name] = @($prop.Value)
        }
        if ($rawPlan.DelayBetweenTests -and -not $PSBoundParameters.ContainsKey('DelayBetweenTests')) {
            $DelayBetweenTests = [int]$rawPlan.DelayBetweenTests
        }
        if ($rawPlan.AutoCleanup -ne $null -and -not $PSBoundParameters.ContainsKey('AutoCleanup')) {
            $AutoCleanup = [bool]$rawPlan.AutoCleanup
        }
        if ($rawPlan.SkipPrereqCheck -ne $null -and -not $PSBoundParameters.ContainsKey('SkipPrereqCheck')) {
            $SkipPrereqCheck = [bool]$rawPlan.SkipPrereqCheck
        }
    } elseif ($TestPlan) {
        foreach ($k in $TestPlan.Keys) {
            $planTestMap[$k] = @($TestPlan[$k])
        }
    }
    $techniquesToRun = @($planTestMap.Keys)
    Write-Host "  [i] Test Plan loaded: $($techniquesToRun.Count) technique(s)" -ForegroundColor Cyan
}
elseif ($RunAll) {
    Write-Host "  [!] Running ALL available techniques" -ForegroundColor Yellow
    $allDirs = Get-ChildItem -Path $AtomicsPath -Directory | Where-Object { $_.Name -match "^T\d+" }
    $techniquesToRun = $allDirs.Name
}
elseif ($Tactic) {
    Write-Host "  [i] Running tactic: $Tactic" -ForegroundColor Cyan
    $validIds = $TacticMap[$Tactic]
    $allDirs = Get-ChildItem -Path $AtomicsPath -Directory | Where-Object { $_.Name -match "^T\d+" }
    foreach ($dir in $allDirs) {
        $baseId = $dir.Name -replace '\..*$', ''
        if ($validIds -contains $baseId) {
            $techniquesToRun += $dir.Name
        }
    }
    Write-Host "      Found $($techniquesToRun.Count) techniques in $Tactic" -ForegroundColor Gray
}
else {
    $rawIds = $TechniqueIds -split "," | ForEach-Object { $_.Trim().ToUpper() }
    # Auto-expand sub-techniques: if user gives T1087, also find T1087.001, T1087.002, etc.
    $expandedIds = @()
    foreach ($rid in $rawIds) {
        $expandedIds += $rid
        # Check if this is a parent technique (no dot) and has sub-technique folders
        if ($rid -notmatch '\.') {
            $subDirs = Get-ChildItem -Path $AtomicsPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^${rid}\.\d+$" }
            if ($subDirs) {
                foreach ($sub in $subDirs) {
                    if ($expandedIds -notcontains $sub.Name) {
                        $expandedIds += $sub.Name
                    }
                }
                Write-Host "  [i] Auto-expanded ${rid}: found $($subDirs.Count) sub-technique(s): $($subDirs.Name -join ', ')" -ForegroundColor Cyan
            }
        }
    }
    $techniquesToRun = $expandedIds
}

if ($techniquesToRun.Count -eq 0) {
    Write-Error "No techniques resolved to run."
    exit 1
}

# -- Initialize Session ------------------------------------------------------
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$sessionId = "ART-$timestamp"
$jsonResultsPath = Join-Path $OutputDir "ART_Results_$timestamp.json"
$dashboardResultsPath = Join-Path $PSScriptRoot "..\dashboard\data\results.json"

# Real-time Excel — single fixed file, all runs append to it
$excelPath = Join-Path $OutputDir "ART_Results.xlsx"

$sessionStartTime = Get-Date
$allResults = @()
$totalTests = 0
$passedTests = 0
$failedTests = 0
$skippedTests = 0

$currentPlatform = "windows"

# -- Import Excel module upfront if needed ------------------------------------
if ($ExportExcel) {
    try {
        Import-Module ImportExcel -Force -ErrorAction Stop
        Write-Host "  [i] Real-time Excel enabled: $excelPath" -ForegroundColor Cyan
        $excelReady = $true
    }
    catch {
        Write-Warning "  ImportExcel module not found. Excel export disabled."
        Write-Warning "  Install with: Install-Module ImportExcel -Scope CurrentUser"
        $excelReady = $false
    }
}
else {
    $excelReady = $false
}

# Load the YAMLs using Get-AtomicTechnique (returns real objects)
$techniques = @()
foreach ($id in $techniquesToRun) {
    try {
        $yamlPath = Join-Path $AtomicsPath "$id\$id.yaml"
        if (Test-Path $yamlPath) {
            $techObj = Get-AtomicTechnique -Path $yamlPath
            if ($techObj) {
                $techniques += $techObj
            }
        } else {
            Write-Warning "YAML not found for $id at $yamlPath"
        }
    }
    catch {
        Write-Warning "Technique $id could not be parsed: $_"
    }
}

if ($techniques.Count -eq 0) {
    Write-Error "No valid techniques loaded from $AtomicsPath."
    exit 1
}

Write-Host "  Loaded $($techniques.Count) technique(s). Starting execution..." -ForegroundColor Green
Write-Host ""

# -- Helper: Write a single result row to Excel in real-time -----------------
function Write-ResultToExcel {
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)] [string]$Path
    )

    $row = [PSCustomObject]@{
        "Technique ID"     = $Result.TechniqueID
        "Technique Name"   = $Result.TechniqueName
        "Tactic"           = $Result.Tactic
        "Test Name"        = $Result.TestName
        "Test #"           = $Result.TestNumber
        "Executor"         = $Result.ExecutorType
        "Start Time"       = $Result.StartTime
        "End Time"         = $Result.EndTime
        "Duration (s)"     = $Result.Duration
        "Status"           = $Result.Status
        "Executed Command" = if ($Result.ExecutedCommand.Length -gt 500) { $Result.ExecutedCommand.Substring(0, 500) + "..." } else { $Result.ExecutedCommand }
        "Command Output"   = if ($Result.CommandOutput.Length -gt 500) { $Result.CommandOutput.Substring(0, 500) + "..." } else { $Result.CommandOutput }
        "Cleanup Status"   = $Result.CleanupStatus
        "Prerequisites"    = if ($Result.PrereqsMet) { "Met" } else { "Not Met" }
        "Hostname"         = $Result.Hostname
        "Username"         = $Result.Username
    }

    # Always append — if file doesn't exist, Export-Excel creates it automatically
    $row | Export-Excel -Path $Path -WorksheetName "Results" -Append -AutoSize -BoldTopRow -FreezeTopRow
}

# -- Execution Loop ----------------------------------------------------------
$techIndex = 0

foreach ($technique in $techniques) {
    $techIndex++

    # FIX Bug #1: Cast TechniqueID to string (it can come as array from YAML parser)
    $techniqueId = if ($technique.attack_technique -is [array]) {
        ($technique.attack_technique -join ", ")
    } else {
        [string]$technique.attack_technique
    }

    $techniqueName = $technique.display_name
    if (-not $techniqueName) { $techniqueName = $techniqueId }
    Write-Host ""
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host "  [$techIndex/$($techniques.Count)] $techniqueId - $techniqueName" -ForegroundColor Cyan
    Write-Host "  =======================================================" -ForegroundColor Cyan

    # Determine which tests to run
    $testsToRun = $technique.atomic_tests

    # Check if specific test numbers are requested (via test plan or parameter)
    $specificNumbers = $null
    if ($planTestMap.ContainsKey($techniqueId)) {
        $specificNumbers = $planTestMap[$techniqueId]
    } elseif ($TestNumbers) {
        $specificNumbers = $TestNumbers
    }

    if ($specificNumbers -and $specificNumbers.Count -gt 0) {
        $testsToRun = @()
        $idx = 0
        foreach ($t in $technique.atomic_tests) {
            $idx++
            if ($specificNumbers -contains $idx) {
                $testsToRun += $t
            }
        }
    }

    if (-not $testsToRun -or $testsToRun.Count -eq 0) {
        Write-Host "  No applicable tests found for $currentPlatform" -ForegroundColor DarkGray
        continue
    }

    $testIndexStart = 0
    foreach ($test in $testsToRun) {
        $testIndexStart++
        $testNum = $technique.atomic_tests.IndexOf($test) + 1

        # Check platform
        $platforms = $test.supported_platforms
        if (-not ($platforms -icontains $currentPlatform -or $platforms -icontains "windows")) {
            Write-Host "    [SKIP] Test #${testNum} is not for $currentPlatform" -ForegroundColor DarkGray
            $skippedTests++
            continue
        }

        $totalTests++
        $testGUID = $test.auto_generated_guid
        $testName = $test.name

        Write-Host ""
        Write-Host "    [*] Test #${testNum}: $testName" -ForegroundColor White
        Write-Host "      GUID: $testGUID" -ForegroundColor DarkGray

        # Get the raw command and clean it up for the report
        $executedCommand = $test.executor.command
        if ($executedCommand) {
            # FIX Bug #3: Handle all common PathToAtomicsFolder patterns
            $executedCommand = $executedCommand -replace '\$PathToAtomicsFolder', $AtomicsPath
            $executedCommand = $executedCommand -replace 'PathToAtomicsFolder', $AtomicsPath
            $executedCommand = $executedCommand -replace "`n", "`r`n"
        }

        $cleanupCommand = $test.executor.cleanup_command
        if ($cleanupCommand) {
            $cleanupCommand = $cleanupCommand -replace '\$PathToAtomicsFolder', $AtomicsPath
            $cleanupCommand = $cleanupCommand -replace 'PathToAtomicsFolder', $AtomicsPath
            $cleanupCommand = $cleanupCommand -replace "`n", "`r`n"
        }
        $executorType = $test.executor.name

        # Resolve inputs
        if ($test.input_arguments) {
            foreach ($arg in $test.input_arguments.GetEnumerator()) {
                $argName = $arg.Key
                $argValue = $arg.Value.default
                $executedCommand = $executedCommand -replace "#{$argName}", $argValue
                if ($cleanupCommand) {
                    $cleanupCommand = $cleanupCommand -replace "#{$argName}", $argValue
                }
            }
        }

        # -- Prerequisite Check -----------------------------------------
        $startTime = Get-Date
        $prereqsMet = $true
        if (-not $SkipPrereqCheck -and $test.dependencies) {
            Write-Host "      Checking prerequisites..." -ForegroundColor DarkGray
            try {
                # In PS 5.1, Write-Host goes to stream 6 (Information). We must redirect *>&1 to capture it.
                $prereqResult = Invoke-AtomicTest $techniqueId -TestGuids $testGUID -CheckPrereqs *>&1 | Out-String
                if ($prereqResult -match "not met|failed|error") {
                    # Try to get them
                    Write-Host "      Attempting to resolve prerequisites..." -ForegroundColor DarkYellow
                    Invoke-AtomicTest $techniqueId -TestGuids $testGUID -GetPrereqs *>&1 | Out-Null
                    # Re-check
                    $prereqResult2 = Invoke-AtomicTest $techniqueId -TestGuids $testGUID -CheckPrereqs *>&1 | Out-String
                    if ($prereqResult2 -match "not met|failed|error") {
                        $prereqsMet = $false
                        Write-Host "      [FAIL] Prerequisites could not be satisfied - skipping test" -ForegroundColor Red
                    }
                }
            }
            catch {
                Write-Host "      [WARN] Prereq check error: $_" -ForegroundColor DarkYellow
            }
        }

        # Skip test if prerequisites are not met
        if (-not $prereqsMet) {
            $skippedTests++
            $endTime = Get-Date
            $result = [PSCustomObject]@{
                SessionID       = $sessionId
                TechniqueID     = $techniqueId
                TechniqueName   = $techniqueName
                ParentTechnique = ($techniqueId -replace '\..*$', '')
                IsSubTechnique  = ($techniqueId -match '\.')
                Tactic          = Get-TacticForTechnique -TechniqueId $techniqueId
                TestName        = $testName
                TestNumber      = $testNum
                TestGUID        = $testGUID
                ExecutorType    = $executorType
                StartTime       = $startTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
                EndTime         = $endTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
                Duration        = 0
                ExecutedCommand = $executedCommand
                CommandOutput   = ""
                Status          = "Skipped (Prereqs)"
                ErrorMessage    = "Prerequisites not met"
                CleanupCommand  = $cleanupCommand
                CleanupStatus   = "Not Run"
                CleanupOutput   = ""
                PrereqsMet      = $false
                Hostname        = $env:COMPUTERNAME
                Username        = "$env:USERDOMAIN\$env:USERNAME"
                Platform        = $currentPlatform
            }
            $allResults += $result
            Write-Host "      Status: Skipped (Prereqs) | Attack was not executed" -ForegroundColor DarkYellow

            if ($excelReady) {
                try {
                    Write-ResultToExcel -Result $result -Path $excelPath
                    Write-Host "      [Excel] Row saved" -ForegroundColor DarkGray
                }
                catch {
                    Write-Warning "      [Excel] Failed to write row: $_"
                }
            }
            continue
        }

        # -- Execute Attack ---------------------------------------------
        $status = "Success"
        $commandOutput = ""
        $errorMessage = ""

        Write-Host "      Executing attack..." -ForegroundColor Yellow

        # FIX Bug #5: Use Start-Transcript to capture Write-Host output
        $transcriptPath = Join-Path $env:TEMP "ART_transcript_$([guid]::NewGuid().ToString('N')).txt"
        try {
            Start-Transcript -Path $transcriptPath -Force | Out-Null
            try {
                Invoke-AtomicTest $techniqueId -TestGuids $testGUID -Confirm:$false 2>&1 | Out-Null
            }
            catch {
                $status = "Failed"
                $errorMessage = $_.Exception.Message
                Write-Host "      [FAIL] Attack threw exception" -ForegroundColor Red
            }
            finally {
                Stop-Transcript | Out-Null
            }
            # Read transcript for command output
            if (Test-Path $transcriptPath) {
                $rawTranscript = Get-Content $transcriptPath -Raw -ErrorAction SilentlyContinue
                if ($rawTranscript) {
                    # Extract everything between the start header and end footer
                    if ($rawTranscript -match '(?s)Transcript started, output file is [^\r\n]+[\r\n]+(.*?)[\r\n]+\*+\s+Windows PowerShell transcript end') {
                        $commandOutput = $Matches[1].Trim()
                    } else {
                        # Fallback if transcript format is weird
                        $commandOutput = $rawTranscript.Trim()
                    }
                }
                Remove-Item $transcriptPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Transcript failed - fall back to basic capture
            try {
                $commandOutput = Invoke-AtomicTest $techniqueId -TestGuids $testGUID -Confirm:$false 2>&1 | Out-String
            }
            catch {
                $status = "Failed"
                $errorMessage = $_.Exception.Message
                $commandOutput = $_.ToString()
                Write-Host "      [FAIL] Attack threw exception" -ForegroundColor Red
            }
        }

        # FIX: Detect ACTUAL failure from output - Invoke-AtomicTest does NOT throw
        # on test failure, it just writes "Exit code: N" to the host.
        if ($status -eq "Success" -and $commandOutput) {
            # Check for non-zero exit codes (positive like 1, or negative like -2146233087)
            if ($commandOutput -match 'Exit code:\s*(-?\d+)' -and $Matches[1] -ne '0') {
                $status = "Failed"
                $errorMessage = "Exit code: $($Matches[1])"
                Write-Host "      [FAIL] Attack failed (exit code $($Matches[1]))" -ForegroundColor Red
            }
            # Check for common error patterns from the test executor
            elseif ($commandOutput -match 'cannot find the path|access is denied|is not recognized as|cannot find the file|not operable|The term .+ is not recognized') {
                $status = "Failed"
                $errorMessage = "Error detected in command output"
                Write-Host "      [FAIL] Attack failed (error in output)" -ForegroundColor Red
            }
            else {
                Write-Host "      [OK] Attack executed" -ForegroundColor Green
            }
            if ($commandOutput) {
                $outLines = ($commandOutput -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                foreach ($line in ($outLines | Select-Object -First 5)) {
                    Write-Host "        > $line" -ForegroundColor DarkGray
                }
                if ($outLines.Count -gt 5) {
                    Write-Host "        > ... ($($outLines.Count - 5) more output lines recorded)" -ForegroundColor DarkGray
                }
            }
        }
        elseif ($status -eq "Success") {
            Write-Host "      [OK] Attack executed" -ForegroundColor Green
        }

        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds

        # == Cleanup ====================================================
        $cleanupStatus = "Not Run"
        $cleanupOutput = ""

        if ($AutoCleanup -and $cleanupCommand) {
            Write-Host "      Running cleanup..." -ForegroundColor DarkGray
            try {
                $cleanupOutput = Invoke-AtomicTest $techniqueId -TestGuids $testGUID -Cleanup -Confirm:$false 2>&1 | Out-String
                $cleanupStatus = "Success"
                Write-Host "      [OK] Tests Finished." -ForegroundColor Green
            }
            catch {
                $cleanupStatus = "Failed"
                $cleanupOutput = $_.ToString()
                Write-Host "      X Cleanup failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        elseif (-not $cleanupCommand) {
            $cleanupStatus = "No Cleanup Defined"
            $cleanupCommand = "N/A"
        }
        else {
            $cleanupStatus = "Skipped (AutoCleanup disabled)"
        }

        # -- Record Result ----------------------------------------------
        if ($status -eq "Success") { $passedTests++ } else { $failedTests++ }

        # FIX Bug #1 & #2: $techniqueId is already a string from line ~240
        $parentTech = $techniqueId -replace '\..*$', ''
        $isSub = $techniqueId -match '\.'

        $result = [PSCustomObject]@{
            SessionID       = $sessionId
            TechniqueID     = $techniqueId
            TechniqueName   = $techniqueName
            ParentTechnique = $parentTech
            IsSubTechnique  = $isSub
            Tactic          = Get-TacticForTechnique -TechniqueId $techniqueId
            TestName        = $testName
            TestNumber      = $testNum
            TestGUID        = $testGUID
            ExecutorType    = $executorType
            StartTime       = $startTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
            EndTime         = $endTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
            Duration        = [math]::Round($duration, 2)
            ExecutedCommand = $executedCommand
            CommandOutput   = $commandOutput.Trim()
            Status          = $status
            ErrorMessage    = $errorMessage
            CleanupCommand  = $cleanupCommand
            CleanupStatus   = $cleanupStatus
            CleanupOutput   = $cleanupOutput.Trim()
            PrereqsMet      = $prereqsMet
            Hostname        = $env:COMPUTERNAME
            Username        = "$env:USERDOMAIN\$env:USERNAME"
            Platform        = $currentPlatform
        }

        $allResults += $result

        Write-Host "      Status: $status | Duration: ${duration}s | Cleanup: $cleanupStatus" -ForegroundColor DarkGray

        # -- REAL-TIME EXCEL: Write this result immediately ----------------
        if ($excelReady) {
            try {
                Write-ResultToExcel -Result $result -Path $excelPath
                Write-Host "      [Excel] Row saved to $excelPath" -ForegroundColor DarkGray
            }
            catch {
                Write-Warning "      [Excel] Failed to write row: $_"
            }
        }

        # -- Delay between tests ----------------------------------------
        if ($techIndex -lt $techniques.Count -or $testIndexStart -lt $testsToRun.Count) {
            if ($DelayBetweenTests -gt 0) {
                Write-Host "      Waiting ${DelayBetweenTests}s before next test..." -ForegroundColor DarkGray
                Start-Sleep -Seconds $DelayBetweenTests
            }
        }
    }
}

$sessionEndTime = Get-Date
$sessionDuration = ($sessionEndTime - $sessionStartTime).TotalMinutes

# -- Build Session Summary ---------------------------------------------------
$sessionData = @{
    SessionInfo = @{
        SessionID          = $sessionId
        StartTime          = $sessionStartTime.ToString("yyyy-MM-dd HH:mm:ss")
        EndTime            = $sessionEndTime.ToString("yyyy-MM-dd HH:mm:ss")
        DurationMinutes    = [math]::Round($sessionDuration, 2)
        Hostname           = $env:COMPUTERNAME
        Username           = "$env:USERDOMAIN\$env:USERNAME"
        Platform           = $currentPlatform
        TechniquesSelected = $techniques.Count
        TotalTests         = $totalTests
        Passed             = $passedTests
        Failed             = $failedTests
        Skipped            = $skippedTests
        SuccessRate        = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 1) } else { 0 }
        AutoCleanup        = $AutoCleanup
        DelayBetweenTests  = $DelayBetweenTests
    }
    Results = $allResults
}

# -- Save JSON Results -------------------------------------------------------
$unifiedJsonPath = Join-Path $OutputDir "ART_Results.json"

# Save session timestamped JSON
$sessionData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonResultsPath -Encoding UTF8 -Force

# Save unified single JSON
$sessionData | ConvertTo-Json -Depth 10 | Out-File -FilePath $unifiedJsonPath -Encoding UTF8 -Force

# Also copy to dashboard data folder
$sessionData | ConvertTo-Json -Depth 10 | Out-File -FilePath $dashboardResultsPath -Encoding UTF8 -Force

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "  |              [OK] Attack Session Complete                 |" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Session Summary:" -ForegroundColor White
Write-Host "    Total Tests:   $totalTests" -ForegroundColor Gray
Write-Host "    Passed:        $passedTests" -ForegroundColor Green
Write-Host "    Failed:        $failedTests" -ForegroundColor Red
Write-Host "    Skipped:       $skippedTests" -ForegroundColor DarkYellow
Write-Host "    Duration:      $([math]::Round($sessionDuration, 2)) minutes" -ForegroundColor Gray
Write-Host "    Success Rate:  $($sessionData.SessionInfo.SuccessRate)%" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Unified Results in results folder:" -ForegroundColor White
if ($excelReady) {
    Write-Host "    Excel Report: $excelPath ($($allResults.Count) tests)" -ForegroundColor Green
}
Write-Host "    JSON Report:  $unifiedJsonPath" -ForegroundColor Green
Write-Host "    Dashboard:    $dashboardResultsPath" -ForegroundColor Gray
Write-Host ""
