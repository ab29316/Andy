# Andy

This repository contains a PowerShell script `Install-Windows11.ps1` that upgrades a Windows 10 machine to Windows 11 using Microsoft's Installation Assistant. The script logs each step, schedules itself to continue after the upgrade, creates a restore point for rollback, and optionally removes several built‑in apps. Updates are installed only after Windows 11 is running.

## Running the script

Run the script from an elevated PowerShell prompt. Many systems block PowerShell scripts by default, so use the `-ExecutionPolicy Bypass` flag:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-Windows11.ps1
```

You can set a more permissive policy for just the current user if preferred:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
```

The script detects a `Restricted` policy and temporarily bypasses it for the running process. It attempts to create a system restore point; if the System Restore service is disabled, it is enabled temporarily.

Before launching the Installation Assistant the script creates a scheduled task that runs at startup under the SYSTEM account. This task re-invokes the script with `-PostUpgrade` so updates and optional bloat removal occur after Windows 11 is installed. The Installation Assistant handles any reboots on its own; once updates finish the scheduled task removes itself.
