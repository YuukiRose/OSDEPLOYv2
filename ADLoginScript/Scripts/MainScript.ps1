# MainScript.ps1

# Import WinPE utilities first
$modulesPath = Join-Path $PSScriptRoot "..\Modules"
Import-Module (Join-Path $modulesPath "WinPEUtil.psm1") -Force

# Verify WinPE environment if required
if (-not (Test-WinPE)) {
    Write-Host "This script must be run in Windows PE environment" -ForegroundColor Red
    exit 1
}

# Initialize WinPE network
if (-not (Initialize-WinPENetwork)) {
    Write-Host "Failed to initialize WinPE network components" -ForegroundColor Red
    exit 1
}

# Import modules using absolute paths
$modulesPath = Join-Path $PSScriptRoot "..\Modules"
Import-Module (Join-Path $modulesPath "DeploymentConfig.psm1") -Force
Import-Module (Join-Path $modulesPath "ADLogin.psm1") -Force
Import-Module (Join-Path $modulesPath "PSDriveMapping.psm1") -Force
Import-Module (Join-Path $modulesPath "GUIModule.psm1") -Force

# Get configuration
$config = Get-DeploymentConfig

function Get-ADCredentials {
    do {
        $credentials = Get-Credential -Message "Please enter your Active Directory credentials"
        if ($credentials) {
            $isValid = Test-ADCredentials -Username $credentials.UserName -Password $credentials.GetNetworkCredential().Password
            
            if (-not $isValid) {
                Write-Host "Invalid credentials, please try again."
            }
        } else {
            Write-Host "Credentials cannot be null. Please try again."
            $isValid = $false
        }
    } while (-not $isValid)
    
    return $credentials
}

# Get credentials
$credentials = Get-ADCredentials

# Use drive mappings from config
foreach ($drive in $config.DriveMappers) {
    New-NetworkDrive -DriveName $drive.DriveLetter -DrivePath $drive.SharePath -Credential $credentials
}

# Use image paths from config
$linuxImagesPath = $config.LinuxImagePath
Show-OSSelectionGUI -LinuxImagesPath $linuxImagesPath