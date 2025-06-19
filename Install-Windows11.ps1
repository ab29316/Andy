# Install-Windows11.ps1
# Example script to upgrade Windows 10 to Windows 11 using Microsoft's
# Windows 11 Installation Assistant. Logs all actions, creates a restore
# point, installs updates, and optionally removes some built in apps.

param(
    [switch]$RemoveBloat
)

$LogFile = "$env:USERPROFILE\install_windows11_full.log"
Start-Transcript -Path $LogFile -Append
Write-Output "Logging to $LogFile"

# Create a system restore point for rollback
Write-Output "Creating system restore point"
Checkpoint-Computer -Description "Pre-Windows11Upgrade" -RestorePointType "MODIFY_SETTINGS"

# Ensure PSWindowsUpdate module for installing updates
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Output "Installing PSWindowsUpdate module"
    Install-PackageProvider -Name NuGet -Force | Out-Null
    Install-Module -Name PSWindowsUpdate -Force | Out-Null
}
Write-Output "Importing PSWindowsUpdate module"
Import-Module PSWindowsUpdate

# Download Windows 11 Installation Assistant and run silently
$InstallerUrl  = "https://go.microsoft.com/fwlink/?linkid=2171764"
$InstallerPath = "$env:USERPROFILE\Downloads\Windows11InstallationAssistant.exe"
Write-Output "Downloading Windows 11 Installation Assistant"
Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
Write-Output "Launching Installation Assistant"
Start-Process -FilePath $InstallerPath -ArgumentList '/quietinstall /skipeula /auto upgrade' -Wait

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

# Install all Windows updates after upgrade
Write-Output "Installing Windows updates"
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot

Stop-Transcript
