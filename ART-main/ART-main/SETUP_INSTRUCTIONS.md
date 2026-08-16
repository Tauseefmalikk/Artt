# ART Setup Instructions

Since you have successfully placed both the `atomics` and `invoke-atomicredteam` folders directly into `C:\AtomicRedTeam\`, you are ready to go!

Our scripts look for the files in that exact folder by default, so you don't even need to pass any custom paths.

## Step 1: Run the Dashboard Setup Script

Open **PowerShell as Administrator** and run:

```powershell
cd C:\Users\TouseefMalik\Desktop\ART\scripts
.\Install-ARTDependencies.ps1
```

This will load the engine you downloaded and install the Excel reporting tool.

## Step 2: Build the Dashboard Catalog

This reads the attacks you just downloaded and builds the visual list for the dashboard:

```powershell
.\Get-ARTTechniques.ps1
```

## Step 3: Start Testing!

Now you can run the attacks. Start with a safe discovery test to verify everything works:

```powershell
# Safe test (just runs ipconfig/netstat)
.\Invoke-ARTAutomation.ps1 -TechniqueIds "T1016"

# Or run multiple
.\Invoke-ARTAutomation.ps1 -TechniqueIds "T1016,T1033,T1082"

# Or run a whole tactic
.\Invoke-ARTAutomation.ps1 -Tactic "Discovery"
```

## Step 4: View Results

- **Dashboard**: Open `C:\Users\TouseefMalik\Desktop\ART\dashboard\index.html` in any web browser.
- **Excel Report**: Check the `C:\Users\TouseefMalik\Desktop\ART\results\` folder.
