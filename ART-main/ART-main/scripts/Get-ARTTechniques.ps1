<#
.SYNOPSIS
    Scans the atomics folder and builds a JSON catalog of all available techniques.

.DESCRIPTION
    Parses Atomic Red Team YAML definitions to create a structured JSON file
    containing technique IDs, names, tactics, platforms, and test counts.
    This catalog is consumed by the SOC dashboard for technique browsing.

.PARAMETER AtomicsPath
    Path to the atomics folder. Default: C:\AtomicRedTeam\atomics

.PARAMETER OutputPath
    Path for the output JSON file. Default: ..\dashboard\data\techniques.json

.EXAMPLE
    .\Get-ARTTechniques.ps1
    .\Get-ARTTechniques.ps1 -AtomicsPath "D:\AtomicRedTeam\atomics"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$AtomicsPath = "C:\AtomicRedTeam\atomics",

    [Parameter()]
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\dashboard\data\techniques.json"),

    [Parameter()]
    [string]$ARTModulePath = "C:\AtomicRedTeam\invoke-atomicredteam"
)

$ErrorActionPreference = "Stop"

Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "  |        ART Technique Catalog Builder                    |" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

# Import ART module
if (Test-Path $ARTModulePath) {
    Import-Module $ARTModulePath -Force -ErrorAction Stop
} else {
    Import-Module invoke-atomicredteam -Force -ErrorAction Stop
}

# Ensure output directory exists
$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

# MITRE ATT&CK Tactic mapping (technique prefix ranges + known mappings)
# This is a simplified mapping; the YAML files contain the actual tactic info
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

function Get-TacticForTechnique {
    param([string]$TechniqueId)
    
    # Get base technique ID (without sub-technique)
    $baseId = ($TechniqueId -split '\.')[0]
    
    $tactics = @()
    foreach ($tactic in $TacticMap.Keys) {
        if ($TacticMap[$tactic] -contains $baseId) {
            $tactics += $tactic
        }
    }
    
    if ($tactics.Count -eq 0) { return "Unknown" }
    return ($tactics -join ", ")
}

Write-Host "  Scanning atomics folder: $AtomicsPath" -ForegroundColor Gray

# Get all technique directories
$techniqueDirs = Get-ChildItem -Path $AtomicsPath -Directory | Where-Object { $_.Name -match "^T\d+" }

Write-Host "  Found $($techniqueDirs.Count) technique directories" -ForegroundColor Gray

$catalog = @()
$processedCount = 0

foreach ($dir in $techniqueDirs) {
    $yamlFile = Join-Path $dir.FullName "$($dir.Name).yaml"
    
    if (-not (Test-Path $yamlFile)) { continue }

    try {
        # Use Get-AtomicTechnique to parse the YAML
        $technique = Get-AtomicTechnique -Path $yamlFile -ErrorAction SilentlyContinue
        
        if ($null -eq $technique) { continue }

        $tests = @()
        $testIndex = 1
        foreach ($test in $technique.atomic_tests) {
            $tests += @{
                TestNumber      = $testIndex
                TestName        = $test.name
                Description     = $test.description
                Platforms       = ($test.supported_platforms -join ", ")
                ExecutorType    = if ($test.executor) { $test.executor.name } else { "manual" }
                HasCleanup      = [bool]($test.executor.cleanup_command)
                GUID            = $test.auto_generated_guid
            }
            $testIndex++
        }

        # Determine supported platforms across all tests
        $allPlatforms = ($technique.atomic_tests | ForEach-Object { $_.supported_platforms } | Sort-Object -Unique) -join ", "

        $entry = @{
            TechniqueID   = $dir.Name
            TechniqueName = $technique.display_name
            Description   = $technique.attack_technique  # brief description from YAML
            Tactic        = Get-TacticForTechnique -TechniqueId $dir.Name
            Platforms     = $allPlatforms
            TestCount     = $technique.atomic_tests.Count
            Tests         = $tests
        }

        $catalog += $entry
        $processedCount++

        if ($processedCount % 50 -eq 0) {
            Write-Host "  Processed $processedCount techniques..." -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "  Failed to parse $($dir.Name): $_"
    }
}

# Sort by Technique ID
$catalog = $catalog | Sort-Object { $_.TechniqueID }

# Build final output
$output = @{
    GeneratedAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    TotalTechniques = $catalog.Count
    Hostname      = $env:COMPUTERNAME
    AtomicsPath   = $AtomicsPath
    Techniques    = $catalog
}

# Export to JSON
$output | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

Write-Host ""
Write-Host "  [OK] Catalog built: $($catalog.Count) techniques with $($catalog | ForEach-Object { $_.TestCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum) total tests" -ForegroundColor Green
Write-Host "  [OK] Output: $OutputPath" -ForegroundColor Green
Write-Host ""
