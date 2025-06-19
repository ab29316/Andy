# Install-Windows11.ps1
#requires -RunAsAdministrator
# Example script to upgrade Windows 10 to Windows 11 using Microsoft's
# Windows 11 Installation Assistant. Logs all actions, creates a restore
# point, installs updates, and optionally removes some built in apps.

param(
    [switch]$RemoveBloat
)

# Ensure the script can run when execution policy is Restricted
$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -eq 'Restricted') {
    Write-Output 'Execution policy is Restricted. Temporarily setting Bypass for this process.'
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}

$LogFile = "$env:USERPROFILE\install_windows11_full.log"
Start-Transcript -Path $LogFile -Append
Write-Output "Logging to $LogFile"

# Create a system restore point for rollback
# Attempt to create a system restore point
$srService = Get-Service -Name 'srservice' -ErrorAction SilentlyContinue
if ($null -ne $srService) {
    $originalStart = $srService.StartType
    $changedStart  = $false
    if ($srService.StartType -eq 'Disabled') {
        Write-Output 'System Restore service is disabled. Enabling temporarily.'
        Set-Service -Name 'srservice' -StartupType Manual
        $changedStart = $true
    }
    if ($srService.Status -ne 'Running') {
        Start-Service -Name 'srservice'
    }
    Write-Output 'Creating system restore point'
    try {
        Checkpoint-Computer -Description 'Pre-Windows11Upgrade' -RestorePointType 'MODIFY_SETTINGS'
    } catch {
        Write-Output "Failed to create restore point: $_"
    }
    if ($changedStart) {
        Set-Service -Name 'srservice' -StartupType $originalStart
    }
} else {
    Write-Output 'System Restore service not available. Skipping restore point.'
}

# Download Windows 11 Installation Assistant and run silently
$InstallerUrl  = "https://go.microsoft.com/fwlink/?linkid=2171764"
$InstallerPath = "$env:USERPROFILE\Downloads\Windows11InstallationAssistant.exe"
Write-Output "Downloading Windows 11 Installation Assistant"
Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
Write-Output "Launching Installation Assistant"
Start-Process -FilePath $InstallerPath -ArgumentList '/quietinstall /skipeula /auto upgrade' -PassThru | Wait-Process

# Wait for upgrade-related processes to finish before continuing
do {
    $running = Get-Process -Name 'Windows11InstallationAssistant','setuphost' -ErrorAction SilentlyContinue
    if ($running) { Start-Sleep -Seconds 30 }
} while ($running)
Write-Output 'Windows 11 installation completed'

# Remove bloatware (example removing built-in apps)
if ($RemoveBloat) {
    Write-Output "Removing built-in apps"
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

# Ensure PSWindowsUpdate module for installing updates
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Output "Installing PSWindowsUpdate module"
    Install-PackageProvider -Name NuGet -Force | Out-Null
    Install-Module -Name PSWindowsUpdate -Force | Out-Null
}
Write-Output "Importing PSWindowsUpdate module"
Import-Module PSWindowsUpdate

# Install all Windows updates after upgrade
Write-Output "Installing Windows updates"
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot

Stop-Transcript
