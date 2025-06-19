# Andy

This repository contains a PowerShell script `Install-Windows11.ps1` that upgrades a Windows 10 machine to Windows 11 using Microsoft's Installation Assistant. The script logs each step, monitors the Windows setup process, schedules itself to continue after the upgrade, creates a restore point for rollback, and optionally removes several built-in apps. Updates are installed only after Windows 11 is running.

## Running the script

Run the script from an elevated PowerShell prompt. Many systems block PowerShell scripts by default, so use the `-ExecutionPolicy Bypass` flag:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-Windows11.ps1
```

You can set a more permissive policy for just the current user if preferred:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
```

The script detects a `Restricted` policy and temporarily bypasses it for the running process. It forcefully enables System Restore even if disabled by policy or service configuration and then creates a restore point so you can easily roll back to Windows 10. Common failures such as download errors or scheduled task registration problems cause the script to exit with a clear message in the log.
When the Installation Assistant closes, the script waits for the Windows setup process to finish and logs the operating system version so you know if the upgrade began.

Before launching the Installation Assistant the script creates a scheduled task that runs at startup under the SYSTEM account. The task uses the full path to `PowerShell.exe` and starts when available, ensuring it actually runs after a reboot. It re-invokes the script with `-PostUpgrade` so updates and optional bloat removal occur after Windows 11 is installed. When updates complete the task deletes itself. If the Installation Assistant exits successfully, the script restarts the computer so the post-upgrade task can continue. The script exits early with a message if the download or task registration fails so you can correct the issue.
