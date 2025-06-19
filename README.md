# Andy

This repository contains a PowerShell script `Install-Windows11.ps1` that upgrades a Windows 10 machine to Windows 11 using Microsoft's Windows 11 Installation Assistant. It logs all actions, creates a restore point for easy rollback, installs updates, and can optionally remove several pre-installed apps to reduce bloat. Key steps emit `Write-Output` messages so the process can be automated and monitored easily.
