# Primary configuration
$Script:ServerName = "SRV01"
$Script:Domain = "yuukirose.com"
$Script:ADDomain = "yuukirose.com"

# Configuration variables
$Script:Config = @{
    # AD Settings
    ADDomain = $Script:ADDomain
    
    # Server Settings
    ServerName = $Script:ServerName
    ServerFQDN = "$Script:ServerName.$Script:Domain"
    ShareName = "Share"
    
    # Network Drives
    DriveMappers = @(
        @{
            DriveLetter = "Z"
            SharePath = "\\$Script:ServerName\Images"
            purpose = "OS Images"  # Optional: Add purpose for clarity
        },
        @{
            DriveLetter = "Y"
            SharePath = "\\$Script:ServerName\Deploy"
            purpose = "Deployment Scripts"  # Optional: Add purpose for clarity
        },
        @{
            DriveLetter = "W"
            SharePath = "\\$Script:ServerName\Logs"
            Purpose = "Logs"  # Optional: Add purpose for clarity
        },
        @{
            DriveLetter = "V"
            SharePath = "\\$Script:ServerName\Images\Drivers"
            Purpose = "Drivers"  # Optional: Add purpose for clarity
        }
    )
    
    # BASE OS Image Pathways
    WindowsImagePath = "\\$Script:ServerName\Images\Windows"
    LinuxImagePath = "\\$Script:ServerName\Images\Linux"

    # Add OSDeployment path
    OSDeploymentPath = "X:\Windows\System32\OSDEPLOY\OSDeployment\OSDeployment.psm1"
}

function Get-DeploymentConfig {
    return $Script:Config
}

function Set-DeploymentServer {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServerName,
        [string]$Domain = $Script:Domain
    )
    
    $Script:ServerName = $ServerName
    $Script:Domain = $Domain
    
    # Update all paths with new server name
    $Script:Config.ServerName = $ServerName
    $Script:Config.ServerFQDN = "$ServerName.$Domain"
    $Script:Config.DriveMappers | ForEach-Object {
        $_.SharePath = $_.SharePath -replace '\\\\[^\\]+\\', "\\$ServerName\"
    }
    $Script:Config.WindowsImagePath = "\\$ServerName\Images\Windows"
    $Script:Config.LinuxImagePath = "\\$ServerName\Images\Linux"
}

function Set-ADDomain {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ADDomain
    )
    
    $Script:ADDomain = $ADDomain
    $Script:Config.ADDomain = $ADDomain
}

Export-ModuleMember -Function Get-DeploymentConfig, Set-DeploymentServer, Set-ADDomain
