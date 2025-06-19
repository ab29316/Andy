# Install-Windows11.ps1
#requires -RunAsAdministrator
# Upgrades Windows 10 to Windows 11 using Microsoft's Installation Assistant.
# Logs all activity and, once Windows 11 is active, installs updates and
# optionally removes built-in apps.

param(
    [switch]$RemoveBloat,
    [switch]$PostUpgrade
)

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

$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -eq 'Restricted') {
    Write-Output 'Execution policy is Restricted. Temporarily setting Bypass for this process.'
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}

$LogFile = "$env:USERPROFILE\install_windows11_full.log"
Start-Transcript -Path $LogFile -Append
Write-Output "Logging to $LogFile"

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
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Install-Module -Name PSWindowsUpdate -Force | Out-Null
    }
    Write-Output 'Importing PSWindowsUpdate module'
    Import-Module PSWindowsUpdate

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
Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing

Write-Output 'Creating scheduled task for post-upgrade actions'
$null = Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$psExe = Join-Path $PSHome 'powershell.exe'
$actionArgs = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" -PostUpgrade"
if ($RemoveBloat) { $actionArgs += ' -RemoveBloat' }
$action = New-ScheduledTaskAction -Execute $psExe -Argument $actionArgs
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

# Create a system restore point for rollback
$srService = Get-Service -Name 'srservice' -ErrorAction SilentlyContinue
if ($null -ne $srService) {
    if ($srService.StartType -eq 'Disabled') {
        Write-Output 'System Restore service is disabled. Enabling.'
        Set-Service -Name 'srservice' -StartupType Manual
    }
    if ($srService.Status -ne 'Running') {
        Start-Service -Name 'srservice'
    }

    Write-Output 'Enabling System Restore on system drive'
    Enable-ComputerRestore -Drive "$env:SystemDrive\" | Out-Null

    Write-Output 'Creating system restore point'
    try {
        Checkpoint-Computer -Description 'Pre-Windows11Upgrade' -RestorePointType 'MODIFY_SETTINGS'
    } catch {
        Write-Output "Failed to create restore point: $_"
    }
} else {
    Write-Output 'System Restore service not available. Skipping restore point.'
}

Write-Output 'Launching Installation Assistant'
$proc = Start-Process -FilePath $InstallerPath -ArgumentList '/quietinstall /skipeula /auto upgrade' -PassThru -Wait
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
