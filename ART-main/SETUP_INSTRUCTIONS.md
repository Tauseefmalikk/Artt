# ART Setup & Execution Instructions

## ⚡ 1-Click Execution (For Clients / Non-Technical Users)

### On Windows:
Double-click the batch file in the root project folder:
```text
RUN_SIMULATION.bat
```

### On macOS / Linux:
Double-click the command file in Finder or run via terminal:
```bash
# Double-click in Finder:
run_simulation.command

# Or run in terminal:
sudo ./run_simulation.sh
```

**Everything is 100% automated:**
1. **Auto-Elevates**: Requests Administrator / Root privileges.
2. **Auto-Installs Dependencies**: Sets up NuGet, `powershell-yaml`, and `ImportExcel`.
3. **Auto-Downloads Atomics**: Automatically downloads and unpacks the Atomic Red Team attack library from GitHub if not already present.
4. **Detects Platform**: Automatically detects `windows`, `macos`, or `linux` and filters tests accordingly.
5. **Executes Test Plan**: Runs all techniques and test numbers defined in `test_plan.json`.
6. **Unified Results**: Produces a **single unified Excel report (`ART_Results.xlsx`)** and **JSON report (`ART_Results.json`)** in the `results/` folder.
7. **Auto-Opens**: Automatically pops open the `results/` folder when done!

---

## 🛠️ Customizing the Test Plan

You and your client can customize the assessment at any time by editing `test_plan.json`:

```json
{
  "Description": "Security Assessment Execution Plan",
  "AutoCleanup": true,
  "DelayBetweenTests": 10,
  "SkipPrereqCheck": false,
  "Tests": {
    "T1059.003": [1, 2, 3],
    "T1016": []
  }
}
```
*(Use `[]` to run all tests for a technique, or specific test numbers like `[1, 3]`)*

---

## 🔬 Manual / Advanced Execution via PowerShell

> **Note on the `atomics` folder**:
> If you have not downloaded the attack definitions yet, you can let the script automatically download and extract them for you:
> ```powershell
> .\Install-ARTDependencies.ps1 -DownloadAtomics
> ```
> Or pass custom locations if stored elsewhere:
> ```powershell
> .\Install-ARTDependencies.ps1 -AtomicsPath "D:\path\to\atomics" -ARTModulePath "D:\path\to\invoke-atomicredteam"
> ```

---

## Step 2: Build the Dashboard Catalog

Scans your atomics folder and builds the JSON catalog for the SOC dashboard:

```powershell
.\Get-ARTTechniques.ps1
```

---

## Step 3: Run Attack Simulations

Run specific techniques, whole tactics, or test lists:

```powershell
# Safe test (runs network discovery: ipconfig, netstat)
.\Invoke-ARTAutomation.ps1 -TechniqueIds "T1016"

# Run multiple techniques
.\Invoke-ARTAutomation.ps1 -TechniqueIds "T1016,T1033,T1082"

# Run an entire tactic
.\Invoke-ARTAutomation.ps1 -Tactic "Discovery"
```

---

## Step 4: View Results

- **Dashboard**: Open `..\dashboard\index.html` in any web browser.
- **Excel Report**: Check the `..\results\` folder for real-time Excel workbooks (`ART_Results_*.xlsx`).
