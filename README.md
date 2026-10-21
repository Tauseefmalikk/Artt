# ⚡ Atomic Red Team Automation Suite (Multi-Platform)

Automated MITRE ATT&CK attack simulation platform built on [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) for SOC teams and security consultants to validate EDR detection capabilities across **Windows**, **macOS**, and **Linux**.

---

## ⚡ 1-Click Master Execution

### 🪟 Windows (1-Click)
1. Double-click **`RUN_SIMULATION.bat`** in the root directory.
2. Accept the Windows UAC Administrator prompt.

### 🍎 macOS & 🐧 Linux (1-Click)
1. Double-click **`run_simulation.command`** in macOS Finder (or run `sudo ./run_simulation.sh` in Terminal).
2. Enter your password when prompted.
3. **Fully automated dependencies**: If PowerShell Core (`pwsh`) is not installed, the runner automatically downloads and installs it for your Mac architecture (Apple Silicon M1/M2/M3/M4 or Intel).

---

## 🚀 What Happens Automatically

On both Windows and macOS/Linux, the 1-click runner:
1. **Installs System Dependencies**: Prepares PowerShell Core (macOS) / NuGet (Windows).
2. **Validates Elevation**: Auto-detects Administrator (Windows) or Root/sudo (macOS/Linux).
3. **Installs PowerShell Modules**: Automatically sets up `powershell-yaml` and `ImportExcel`.
4. **Downloads Atomics**: Automatically downloads and unpacks the Atomic Red Team attack library from GitHub if not found locally.
5. **Detects Platform**: Automatically identifies `windows`, `macos`, or `linux` and loads the platform-specific test plan.
6. **Executes Test Plan**: Runs all techniques and test numbers defined in [`test_plan.json`](./test_plan.json) in a single unified session with live output streaming.
7. **Produces Unified Reports**: Saves real-time Excel (`results/ART_Results.xlsx`) and JSON (`results/ART_Results.json`).
8. **Pops Open Results**: Automatically opens the `results/` folder upon completion.

---

## 🛠️ Multi-Platform Test Plan (`test_plan.json`)

The test plan at [`test_plan.json`](./test_plan.json) automatically separates tests by operating system:

```json
{
  "Description": "Atomic Red Team - Multi-Platform Security Assessment Plan",
  "AutoCleanup": true,
  "DelayBetweenTests": 10,
  "SkipPrereqCheck": false,
  "Platforms": {
    "windows": {
      "T1059.003": [1, 2, 3],
      "T1059.005": [1, 3],
      "T1059.007": [1, 2],
      "T1082": [1, 2],
      "T1016": [1]
    },
    "macos": {
      "T1082": [1, 2],
      "T1016": [1],
      "T1033": [1],
      "T1059.002": [1, 2],
      "T1059.004": [1, 2]
    }
  }
}
```

### How the Engine Knows What to Run:
1. **Automatic OS Selection**: When running on Windows, the runner picks `Platforms.windows`. When running on macOS, it automatically picks `Platforms.macos`.
2. **Safety YAML Filter**: Each atomic test in MITRE ATT&CK has a `supported_platforms` field in its YAML. The runner checks this before running any test. If a test is not for the current OS, it is safely skipped without throwing errors.
3. **Run All Tests for a Technique**: Set `[]` (empty list) for any technique, e.g. `"T1082": []`, and the engine will run all tests for that technique that match your OS.

---

## 🔬 Manual Terminal Execution

You can also run attacks directly using PowerShell:

### Windows (PowerShell 5.1+ or pwsh):
```powershell
powershell.exe -ExecutionPolicy Bypass -File "./ART-main/scripts/Start-ARTAutomation.ps1"
```

### macOS / Linux (PowerShell Core 7+):
```bash
sudo pwsh -ExecutionPolicy Bypass -File "./ART-main/scripts/Start-ARTAutomation.ps1"
```

---

## 📊 Viewing Results

- **Excel Report**: Open `results/ART_Results.xlsx` in Excel, LibreOffice, or Numbers.
- **JSON Output**: Stored at `results/ART_Results.json`.
- **SOC Web Dashboard**: Open `ART-main/dashboard/index.html` in your web browser.
