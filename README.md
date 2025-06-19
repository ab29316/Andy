# Andy

This repository contains a PowerShell script `Install-Windows11.ps1` that upgrades a Windows 10 machine to Windows 11 using Microsoft's Windows 11 Installation Assistant. It logs all actions, creates a restore point for easy rollback, and can optionally remove several pre-installed apps to reduce bloat. Key steps emit `Write-Output` messages so the process can be automated and monitored easily. After the assistant finishes, the script installs all available updates.

## Running the script

Many systems block PowerShell scripts by default. Run the script from an elevated
PowerShell prompt using the `-ExecutionPolicy Bypass` flag:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-Windows11.ps1
```

You can instead set a more permissive policy for just the current user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
```

The script also detects a `Restricted` policy and temporarily bypasses it for
the running process.

The script tries to create a system restore point. If the "System Restore"
service is disabled, it will enable the service temporarily so the restore point
can be created, then revert the service to its original state.
