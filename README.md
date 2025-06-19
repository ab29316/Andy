# Andy

This repository contains a PowerShell script `Install-Windows11.ps1` that upgrades a Windows 10 machine to Windows 11 using Microsoft's Installation Assistant. The script logs each step, creates a restore point for rollback, and optionally removes several built‑in apps. Updates are installed only after Windows 11 is running.

## Running the script

Run the script from an elevated PowerShell prompt. Many systems block PowerShell scripts by default, so use the `-ExecutionPolicy Bypass` flag:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-Windows11.ps1
```

You can set a more permissive policy for just the current user if preferred:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
```

The script detects a `Restricted` policy and temporarily bypasses it for the running process. It also attempts to create a system restore point. If the System Restore service is disabled, it is enabled temporarily.

After downloading and running the Installation Assistant, the script checks its exit code. If the upgrade is successful, the assistant is removed and the computer reboots. A scheduled task then launches the script again to install all Windows updates (and optionally remove bloat) once Windows 11 is in place.
