# ART Setup & Execution Instructions

## ⚡ 1-Click Execution (For Clients / Non-Technical Users)

Simply clone or unzip the repository, and **double-click** the batch file in the project folder:

```text
RUN_SIMULATION.bat
```

**Everything is 100% automated:**
1. **Auto-Elevates**: Prompts standard Windows UAC prompt (click *Yes*).
2. **Auto-Installs Dependencies**: Sets up NuGet, `powershell-yaml`, and `ImportExcel`.
3. **Auto-Downloads Atomics**: Automatically downloads and unpacks the Atomic Red Team attack library from GitHub if not already present.
4. **Executes Test Plan**: Runs all techniques and test numbers defined in `test_plan.json`.
5. **Unified Results**: Produces a **single unified Excel report (`ART_Results.xlsx`)** and **JSON report (`ART_Results.json`)** in the `results\` folder.
6. **Auto-Opens**: Automatically pops open the `results\` folder in Windows Explorer when done!

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
