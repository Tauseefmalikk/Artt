# ⚡ ART Automation Suite — Atomic Red Team for SOC Teams

Automated MITRE ATT&CK attack simulation platform built on [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) for SOC teams to test and validate EDR detection capabilities.

---

## 🏗 Architecture

```
ART/
├── scripts/                            # PowerShell automation engine
│   ├── Install-ARTDependencies.ps1     # One-time dependency setup
│   ├── Get-ARTTechniques.ps1           # Build technique catalog JSON
│   ├── Invoke-ARTAutomation.ps1        # Core attack runner
│   └── Export-ARTReport.ps1            # Excel report generator
├── dashboard/                          # Web-based SOC dashboard
│   ├── index.html                      # Main UI
│   ├── style.css                       # Premium dark-mode styling
│   ├── app.js                          # Dashboard logic
│   └── data/                           # JSON data consumed by dashboard
│       ├── results.json                # Attack execution results
│       └── techniques.json             # Available technique catalog
├── results/                            # Output folder (auto-created)
│   ├── ART_Results_<timestamp>.json    # JSON results
│   ├── ART_Report_<timestamp>.xlsx     # Excel reports
│   └── logs/                           # Raw execution logs
└── README.md
```

---

## 📋 Prerequisites

- **Windows**: Windows 10/11 or Server 2016+ with PowerShell 5.1+ (Administrator)
- **macOS / Linux**: macOS 11+ or Linux with PowerShell Core (`pwsh` 7+) (root/sudo)
  - Install PowerShell Core on macOS: `brew install --cask powershell`
- **Internet access** (for initial setup — downloads ART modules)

---

## ⚡ 1-Click Execution (For Clients & Automated Assessments)

### On Windows:
1. Double-click **`RUN_SIMULATION.bat`** in the project folder.
2. Accept the Windows UAC Administrator prompt.

### On macOS / Linux:
1. Double-click **`run_simulation.command`** in Finder (or run `sudo ./run_simulation.sh` in Terminal).
2. Enter your password when prompted.
3. If PowerShell Core (`pwsh`) is not installed, the runner automatically downloads and installs it for your Mac architecture (Apple Silicon / Intel).

**Everything runs automatically on both platforms:**
- Auto-installs missing dependencies (PowerShell Core, `powershell-yaml`, `ImportExcel`).
- Auto-checks Administrator / Root privileges.
- Auto-downloads the `atomics` folder from GitHub if not already present.
- Auto-detects operating system (`windows`, `macos`, `linux`) and selects matching tests from `test_plan.json`.
- Executes tests defined in **`test_plan.json`**.
- Saves a **single unified Excel report (`ART_Results.xlsx`)** and JSON report in the **`results/`** folder.
- Automatically opens the `results/` folder upon completion.

---

## 🚀 Advanced / Manual PowerShell Execution

### Step 1: Install Dependencies (One-time)

Run on the target VM as Administrator:

```powershell
cd .\scripts
.\Install-ARTDependencies.ps1
```

This installs:
- **Invoke-AtomicRedTeam** — the ART execution engine
- **Atomics** — attack definition YAML files
- **ImportExcel** — Excel export (no Office needed)

### Step 2: Build Technique Catalog

```powershell
.\Get-ARTTechniques.ps1
```

Creates `dashboard/data/techniques.json` with all available techniques.

### Step 3: Run Attacks

```powershell
# Run specific techniques
.\Invoke-ARTAutomation.ps1 -TechniqueIds "T1016,T1059.001,T1003"

# Run all techniques in a tactic
.\Invoke-ARTAutomation.ps1 -Tactic "Discovery"

# Run with custom settings
.\Invoke-ARTAutomation.ps1 -TechniqueIds "T1082,T1033" -DelayBetweenTests 60 -AutoCleanup:$true

# Run ALL techniques (use with caution!)
.\Invoke-ARTAutomation.ps1 -RunAll
```

### Step 4: View Results

**Option A — Dashboard:**
Open `dashboard/index.html` in any browser. Results load automatically.

**Option B — Excel:**
Results are exported to `results/ART_Report_<timestamp>.xlsx`.

---

## 📊 What Gets Captured

For **every attack test**, the suite captures:

| Field | Description |
|---|---|
| Technique ID | MITRE ATT&CK ID (e.g., T1059.001) |
| Technique Name | Human-readable name |
| Tactic | ATT&CK tactic (Execution, Discovery, etc.) |
| Test Name | Specific test variant name |
| Test GUID | Unique test identifier |
| **Start Time** | Precise execution start |
| **End Time** | Precise execution end |
| **Duration** | Elapsed seconds |
| **Executed Command** | The actual command that ran |
| **Command Output** | Full stdout/stderr capture |
| **Status** | Success or Failed |
| **Cleanup Command** | Cleanup command defined for the test |
| **Cleanup Status** | Whether cleanup succeeded |
| Cleanup Output | Output from cleanup execution |
| Prerequisites Met | Whether prereqs were satisfied |
| Hostname | Target machine name |
| Username | User context |

---

## 🎨 Dashboard Features

The web dashboard (`dashboard/index.html`) provides:

### 📊 Results Tab
- **Stats overview** — total tests, pass/fail counts, success rate, duration
- **Session info** — host, user, start/end times
- **Interactive table** — click any row to expand and see the full executed command, output, cleanup details
- **Filtering** — search by technique/command, filter by status, tactic, cleanup result
- **Sorting** — click any column header to sort

### 🎯 Techniques Tab
- Browse all available ART techniques
- Filter by tactic, platform (Windows/Linux/macOS)
- Search by ID or name
- Click to select techniques for the attack launcher

### 🚀 Launcher Tab
- Configure attack parameters (delay, cleanup, prereq skip)
- Select techniques manually or from the browser
- **Generate the exact PowerShell command** to copy and run

### 🗺️ ATT&CK Map Tab
- MITRE ATT&CK matrix heat map
- Color-coded: green (passed), red (failed), amber (mixed), gray (untested)
- Visual coverage at a glance

---

## 📈 Excel Reports

Reports are multi-sheet `.xlsx` workbooks:

1. **Summary** — session overview, pass/fail counts, target info
2. **Detailed Results** — every field for every test, auto-filtered
3. **By Tactic** — breakdown by ATT&CK tactic with success rates
4. **Timeline** — chronological execution view

Features:
- Conditional formatting (green/red status highlighting)
- Frozen headers and auto-filters
- Auto-sized columns
- No Microsoft Office needed (uses ImportExcel module)

---

## ⚙️ Script Parameters

### `Invoke-ARTAutomation.ps1`

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-TechniqueIds` | String | — | Comma-separated technique IDs |
| `-Tactic` | String | — | Run all techniques in a tactic |
| `-RunAll` | Switch | — | Run every technique |
| `-TestNumbers` | Int[] | All | Specific test numbers to run |
| `-AutoCleanup` | Bool | `$true` | Auto-run cleanup after each test |
| `-DelayBetweenTests` | Int | `30` | Seconds between tests (EDR processing time) |
| `-SkipPrereqCheck` | Switch | `$false` | Skip prerequisite validation |
| `-ExportExcel` | Bool | `$true` | Auto-generate Excel report |
| `-OutputDir` | String | `..\results` | Output directory |
| `-AtomicsPath` | String | Auto-detected | Path to atomics folder (checks project root, env vars, etc.) |
| `-ARTModulePath` | String | Auto-detected | Path to invoke-atomicredteam module folder |

---

## ⚠️ Important Notes

1. **Run on an isolated VM** — These are real attack simulations. Never run on production systems.
2. **Auto-Cleanup is enabled by default** — Tests are reversed after execution. Disable with `-AutoCleanup:$false` if you want artifacts to persist for EDR analysis.
3. **30-second delay by default** — This gives your EDR time to detect and log each attack before the next one fires. Adjust with `-DelayBetweenTests`.
4. **Administrator required** — Many techniques require elevated privileges.
5. **Dashboard is static HTML** — No server needed. Just open `index.html` in a browser.

---

## 📂 Loading Results in Dashboard

The dashboard auto-loads from `dashboard/data/results.json`. You can also:
1. Click **📂 Load Results** button in the header
2. Select any `ART_Results_*.json` file from the `results/` folder
3. Results display immediately

---

## 🤝 Workflow for SOC Teams

1. **Prepare**: Run `Install-ARTDependencies.ps1` on your test VM
2. **Plan**: Use the dashboard Techniques tab to browse and select attacks
3. **Launch**: Use the Launcher tab to generate the PowerShell command
4. **Execute**: Run the command on your VM
5. **Analyze**: Open the dashboard to review results, check the ATT&CK heat map
6. **Report**: Use the Excel report for documentation and stakeholder reporting
7. **Validate**: Compare results against your EDR/SIEM alerts to identify detection gaps
