# Install-Windows11.ps1
#requires -RunAsAdministrator
# Upgrades Windows 10 to Windows 11 using Microsoft's Installation Assistant.
# Logs all activity and, once Windows 11 is active, installs updates and
# optionally removes built-in apps. Attempts to handle common failures so the
# upgrade can continue unattended.

param(
    [switch]$RemoveBloat,
    [switch]$PostUpgrade,
    [string]$Edition,
    [string]$Language,
    [string]$InstallationFolder,
    [string[]]$AssistantExtraSwitches,
    [switch]$EnableTelemetry
)

Set-StrictMode -Version Latest

trap {
    Write-Output "Unhandled error: $_"
    Stop-Transcript
    exit 1
}

function Wait-SetupHost {
    param([int]$TimeoutMinutes = 60)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $started = $false
    while ((Get-Date) -lt $deadline) {
        $proc = Get-Process -Name SetupHost -ErrorAction SilentlyContinue
        if ($proc) {
            if (-not $started) {
                Write-Output 'SetupHost detected. Waiting for it to finish...'
                $started = $true
            }
        } elseif ($started) {
            Write-Output 'SetupHost process exited'
            return $true
        }
        Start-Sleep -Seconds 10
    }
    Write-Output 'Timed out waiting for SetupHost'
    return $false
}

function Ensure-RestorePoint {
    Write-Output 'Ensuring System Restore can create a restore point'
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore'
    if (Test-Path $policyPath) {
        foreach ($name in 'DisableSR','DisableConfig','DisableMonitoring') {
            if (Get-ItemProperty -Path $policyPath -Name $name -ErrorAction SilentlyContinue) {
                Set-ItemProperty -Path $policyPath -Name $name -Value 0 -Force
            }
        }
    }
    $services = 'srservice','vss','swprv'
    foreach ($svc in $services) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            if ($svcObj.StartType -eq 'Disabled') {
                Write-Output "Service $svc is disabled. Enabling."
                Set-Service -Name $svc -StartupType Manual
            }
            if ($svcObj.Status -ne 'Running') {
                try {
                    Start-Service -Name $svc -ErrorAction Stop
                } catch {
                    Write-Output "Failed to start service ${svc}: $_"
                }
            }
        }
    }
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" | Out-Null
    } catch {
        Write-Output "Failed to enable System Restore: $_"
    }
    Write-Output 'Creating system restore point'
    try {
        Checkpoint-Computer -Description 'Pre-Windows11Upgrade' -RestorePointType 'MODIFY_SETTINGS'
        Write-Output 'Restore point created'
    } catch {
        Write-Output "Failed to create restore point: $_"
    }
}

function Invoke-SafeDownload {
    param(
        [string]$Url,
        [string]$Destination
    )
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Output "Failed to download ${Url}: $_"
        Stop-Transcript
        exit 1
    }
}

function Assert-Windows10 {
    $productName = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
    if ($productName -notlike '*Windows 10*' -and -not $PostUpgrade) {
        Write-Output "System is already upgraded ($productName). Exiting."
        Stop-Transcript
        exit 0
    }
}

$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -eq 'Restricted') {
    Write-Output 'Execution policy is Restricted. Temporarily setting Bypass for this process.'
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}

$LogFile = "$env:USERPROFILE\install_windows11_full.log"
Start-Transcript -Path $LogFile -Append
Write-Output "Logging to $LogFile"

Assert-Windows10

$taskName = 'Windows11PostUpgrade'
$scriptPath = $PSCommandPath

if ($PostUpgrade) {
    Write-Output 'Running post-upgrade tasks'
    # This section runs after the reboot when Windows 11 is installed
    $productName = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
    if ($productName -notlike '*Windows 11*') {
        Write-Output 'Still not on Windows 11. Will run again after next reboot.'
        Stop-Transcript
        return
    }

    $assistantUninstall = 'C:\\Windows10Upgrade\\Windows10UpgraderApp.exe'
    if (Test-Path $assistantUninstall) {
        Write-Output 'Removing Installation Assistant'
        Start-Process -FilePath $assistantUninstall -ArgumentList '/ForceUninstall' -Wait
    }

    if ($RemoveBloat) {
        Write-Output 'Removing built-in apps'
        $Bloatware = @(
            'Microsoft.3DBuilder',
            'Microsoft.BingNews',
            'Microsoft.GetHelp',
            'Microsoft.Getstarted',
            'Microsoft.MicrosoftOfficeHub',
            'Microsoft.MicrosoftSolitaireCollection',
            'Microsoft.MixedReality.Portal',
            'Microsoft.People',
            'Microsoft.SkypeApp',
            'Microsoft.Xbox.TCUI',
            'Microsoft.XboxApp',
            'Microsoft.XboxGameOverlay',
            'Microsoft.XboxGamingOverlay',
            'Microsoft.XboxIdentityProvider',
            'Microsoft.XboxSpeechToTextOverlay',
            'Microsoft.ZuneMusic',
            'Microsoft.ZuneVideo'
        )
        foreach ($app in $Bloatware) {
            Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
        }
    }

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Output 'Installing PSWindowsUpdate module'
        try {
            Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
            Install-Module -Name PSWindowsUpdate -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Output "Failed to install PSWindowsUpdate: $_"
            Stop-Transcript
            exit 1
        }
    }
    Write-Output 'Importing PSWindowsUpdate module'
    Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue

    Write-Output 'Installing Windows updates'
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
    if (Get-WURebootStatus) {
        Write-Output 'Reboot required after updates'
        Restart-Computer -Force
        Write-Output 'Post-upgrade tasks completed; rebooting'
    } else {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output 'Updates installed. Task removed.'
        Write-Output 'Post-upgrade tasks completed'
        Stop-Transcript
    }
    return
}

# ------ Pre-upgrade section ------


$InstallerUrl  = 'https://go.microsoft.com/fwlink/?linkid=2171764'
$InstallerPath = "$env:USERPROFILE\Downloads\Windows11InstallationAssistant.exe"
Write-Output 'Downloading Windows 11 Installation Assistant'
Invoke-SafeDownload -Url $InstallerUrl -Destination $InstallerPath
if (-not (Test-Path $InstallerPath)) {
    Write-Output 'Failed to download Installation Assistant. Aborting.'
    Stop-Transcript
    exit 1
}

# Build command line switches for the Installation Assistant.
# Many undocumented flags exist, but most are unreliable. Use a
# compact set that mirrors setup.exe functionality.
$assistantSwitches = @(
    '/Install',                # start the upgrade
    '/SkipEULA',              # pre-accept license
    '/QuietInstall',          # run silently
    '/SkipCompatCheck',       # bypass hardware checks
    '/SetPriorityLow',        # reduce resource usage
    '/PreventWUUpgrade',      # avoid Windows Update interference
    '/MinimizeToTaskBar',
    '/ShowProgressInTaskBarIcon',
    '/UninstallUponUpgrade',  # clean up when done
    '/ForceUninstall',
    '/NoRestartUI'
)
if ($EnableTelemetry) { $assistantSwitches += '/EnableTelemetry' }
if ($InstallationFolder) { $assistantSwitches += "/InstallationFolder:`"$InstallationFolder`"" }
if ($Edition) { $assistantSwitches += "/Edition:$Edition" }
if ($Language) { $assistantSwitches += "/Language:$Language" }
if ($AssistantExtraSwitches) { $assistantSwitches += $AssistantExtraSwitches }
$assistantArgs = $assistantSwitches -join ' '

Write-Output 'Creating scheduled task for post-upgrade actions'
$null = Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$psExe = Join-Path $PSHome 'powershell.exe'
$actionArgs = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" -PostUpgrade"
if ($RemoveBloat) { $actionArgs += ' -RemoveBloat' }
$action = New-ScheduledTaskAction -Execute $psExe -Argument $actionArgs
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}
catch {
    Write-Output "Failed to register scheduled task: $_"
    Stop-Transcript
    exit 1
}

# Create a system restore point for rollback
Ensure-RestorePoint

Write-Output 'Launching Installation Assistant'
$proc = Start-Process -FilePath $InstallerPath -ArgumentList $assistantArgs -PassThru -Wait
$exitCode = $proc.ExitCode
Write-Output "Installation Assistant exited with code $exitCode"
if (Wait-SetupHost -TimeoutMinutes 120) { Write-Output 'Setup phase finished' } else { Write-Output 'Setup phase timeout or failure' }
$productName = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
Write-Output "OS after setup: $productName"
if ($productName -like '*Windows 11*') { Write-Output 'Upgrade detected' } else { Write-Output 'Upgrade not detected' }
if ($exitCode -ne 0) {
    Write-Output 'Installation Assistant reported an error. Aborting.'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Transcript
    exit $exitCode
}

$assistantUninstall = 'C:\Windows10Upgrade\Windows10UpgraderApp.exe'
if (Test-Path $assistantUninstall) {
    Write-Output 'Uninstalling Installation Assistant'
    Start-Process -FilePath $assistantUninstall -ArgumentList '/ForceUninstall' -Wait
}
Remove-Item $InstallerPath -ErrorAction SilentlyContinue
Write-Output 'Installation Assistant completed successfully. Restarting now so post-upgrade tasks can run.'
Stop-Transcript
Restart-Computer -Force
