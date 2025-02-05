# Module for OS Deployment functions

# Import required modules from ScriptRoot
Import-Module "$PSScriptRoot\DeploymentConfig.psm1" -Force
Import-Module "$PSScriptRoot\WindowsDeployment.psm1" -Force
Import-Module "$PSScriptRoot\GUIModule.psm1" -Force
Import-Module "$PSScriptRoot\ADLogin.psm1" -Force
Import-Module "$PSScriptRoot\PSDriveMapping.psm1" -Force
Import-Module "$PSScriptRoot\Logging.psm1" -Force

# Add Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms

# Get configuration
$config = Get-DeploymentConfig()

# Update configuration variables using config values
$Script:LogBasePath = Join-Path "\\$($config.ServerName)" "Logs"
$Script:Windows10Path = Join-Path $config.WindowsImagePath "10"
$Script:Windows11Path = Join-Path $config.WindowsImagePath "11"
$Script:UnattendPath = Join-Path $config.WindowsImagePath "Config\unattend.xml"
$Script:CustomersPath = Join-Path "\\$($config.ServerName)" "Images\Customers"
$Script:DriverBasePath = Join-Path "\\$($config.ServerName)" "Images\Drivers"

# Update module path definition
$Script:ModulePath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Remove old build paths and add build folders
$Script:Win10Builds = @{
    '22H2' = "22H2"
}

$Script:Win11Builds = @{
    '23H2' = "23H2"
    '24H2' = "24H2"
}

function Get-LogPath {
    param (
        [string]$CustomerName,
        [string]$OrderNumber,
        [string]$SerialNumber
    )
    
    # Wait for and verify drive availability
    $driveRetries = 3
    while ($driveRetries -gt 0) {
        if (Test-Path "Z:\") {
            break
        }
        Write-Host "Waiting for Z: drive to become available..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        $driveRetries--
    }
    
    if (-not (Test-Path "Z:\")) {
        [System.Windows.Forms.MessageBox]::Show(
            "Drive Z: is not available. Please ensure network drives are mapped.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        throw "Drive mapping failed"
    }
    
    # Check if base log path exists
    if (-not (Test-Path $Script:LogBasePath)) {
        New-Item -Path $Script:LogBasePath -ItemType Directory -Force | Out-Null
        [System.Windows.Forms.MessageBox]::Show(
            "Log Base Path Not Found.`nCreated Base Log Directory at:`n$Script:LogBasePath",
            "Log Path Warning",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }

    if (-not $CustomerName) {
        $CustomerName = "Unknown"
    }
    if (-not $OrderNumber) {
        $OrderNumber = Get-Date -Format "yyyyMMdd"
    }
    if (-not $SerialNumber) {
        $SerialNumber = (Get-WmiObject Win32_BIOS).SerialNumber
        if (-not $SerialNumber) {
            $SerialNumber = "Unknown"
        }
    }

    $logPath = Join-Path $Script:LogBasePath "$CustomerName\$OrderNumber\$SerialNumber"
    if (-not (Test-Path $logPath)) {
        New-Item -Path $logPath -ItemType Directory -Force | Out-Null
    }
    return Join-Path $logPath "OSDeployment.log"
}

function Test-DeploymentPrerequisites {
    param(
        [switch]$Detailed
    )
    
    $prerequisites = @{
        DiskSpace = $false
        NetworkConnection = $false
        AdminRights = $false
        RequiredTools = $false
    }

    try {
        # Check disk space
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        $prerequisites.DiskSpace = ($disk.FreeSpace / 1GB) -gt 20

        # Import DriveMaps to get server address
        Import-Module "$Script:ModulePath\DriveMaps.psm1" -DisableNameChecking
        # Check network using deployment server
        $prerequisites.NetworkConnection = Test-Connection -ComputerName $ServerAddress -Count 1 -Quiet

        # Check admin rights
        $prerequisites.AdminRights = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        # Check required tools
        $prerequisites.RequiredTools = $null -ne (Get-Command dism.exe -ErrorAction SilentlyContinue)

        if ($Detailed) {
            return $prerequisites
        }
        
        return -not ($prerequisites.Values -contains $false)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error checking prerequisites: $_",
            "Prerequisite Check Failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }
}

function Get-WindowsImagePath {
    param (
        [string]$Version,
        [string]$Build
    )

    $basePath = if ($Version -eq "10") { $Script:Windows10Path } else { $Script:Windows11Path }
    $buildPath = Join-Path $basePath $Build
    
    # Look for both install.wim and install.esd
    $wimFile = Get-ChildItem -Path $buildPath -Filter "install.wim" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    $esdFile = Get-ChildItem -Path $buildPath -Filter "install.esd" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($wimFile) {
        return @{
            Path = $wimFile.FullName
            Type = "wim"
        }
    }
    elseif ($esdFile) {
        return @{
            Path = $esdFile.FullName
            Type = "esd"
        }
    }
    
    [System.Windows.Forms.MessageBox]::Show(
        "No install.wim or install.esd found in $buildPath",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return $null
}

function Get-CustomerImageDetails {
    # Create customer base path if it doesn't exist
    if (-not (Test-Path $Script:CustomersPath)) {
        New-Item -Path $Script:CustomersPath -ItemType Directory -Force | Out-Null
        [System.Windows.Forms.MessageBox]::Show(
            "Customer Folder Not Found.`nCreated Base Folder.`nPlease Add ImageIndex Folder & Install.wim",
            "Customer Folder Warning",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }

    # Scan customer folders and build structure
    $customers = Get-ChildItem -Path $Script:CustomersPath -Directory -ErrorAction SilentlyContinue
    $imageDetails = @{}

    foreach ($customer in $customers) {
        $imageDetails[$customer.Name] = @{}
        $indexes = Get-ChildItem -Path $customer.FullName -Directory -ErrorAction SilentlyContinue
        
        foreach ($index in $indexes) {
            $imageDetails[$customer.Name][$index.Name] = @{}
            $deviceTypes = Get-ChildItem -Path $index.FullName -Directory -ErrorAction SilentlyContinue
            
            foreach ($deviceType in $deviceTypes) {
                $wimPath = Join-Path $deviceType.FullName "install.wim"
                if (Test-Path $wimPath) {
                    $imageDetails[$customer.Name][$index.Name][$deviceType.Name] = $wimPath
                }
            }
        }
    }
    return $imageDetails
}

# Update Get-MatchingDriverPath function
function Get-MatchingDriverPath {
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $manufacturer = $computerSystem.Manufacturer
        $model = $computerSystem.Model

        # Look for manufacturer\model match
        $driverPath = Join-Path $Script:DriverBasePath "$manufacturer\$model"
        if (Test-Path $driverPath) {
            Write-Log -Message "Found driver match for $manufacturer $model" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
            return $driverPath
        }
        
        # No drivers found - ask user if they want to harvest
        $message = @"
No drivers found for:
Manufacturer: $manufacturer
Model: $model

Would you like to harvest drivers from this device before continuing with OS deployment?
"@
        $result = [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Driver Harvest Required",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            # Import from same directory
            Import-Module "$Script:ModulePath\DriverHarvest.psm1" -Force -DisableNameChecking
            $success = Start-DriverHarvest
            
            if ($success -and (Test-Path $driverPath)) {
                Write-Log -Message "Drivers successfully harvested to $driverPath" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
                return $driverPath
            } else {
                Write-Log -Message "Driver harvest failed or path not found after harvest" -Type Warning -LogPath $Script:LogPath -Component "OSDeployment"
                return $null
            }
        }

        Write-Log -Message "No matching drivers found for $manufacturer $model" -Type Warning -LogPath $Script:LogPath -Component "OSDeployment"
        return $null
    }
    catch {
        Write-Log -Message "Error finding matching drivers: $_" -Type Error -LogPath $Script:LogPath -Component "OSDeployment"
        return $null
    }
}

function Add-DriversToImage {
    param (
        [string]$WindowsDrive,
        [string]$DriverPath
    )
    try {
        Write-Log -Message "Adding drivers from: $DriverPath" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
        $result = Start-Process -FilePath "dism.exe" -ArgumentList "/Image:${WindowsDrive}:\ /Add-Driver /Driver:$DriverPath /Recurse" -NoNewWindow -Wait -PassThru

        if ($result.ExitCode -eq 0) {
            Write-Log -Message "Drivers added successfully" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
            return $true
        }
        else {
            Write-Log -Message "Failed to add drivers. DISM exit code: $($result.ExitCode)" -Type Error -LogPath $Script:LogPath -Component "OSDeployment"
            return $false
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error adding drivers: $_",
            "Driver Installation Failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }
}

function Initialize-DiskPartitioning {
    Write-Log -Message "Step 1 - Prepare Disk Partitions" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
    wpeutil UpdateBootInfo
    $key = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control"
    $value = "PEFirmwaretype"
    $FirmwareType = (Get-ItemProperty -Path $key -Name $value).$value

    if ($FirmwareType -eq 1) {
        Write-Log -Message "Detected firmware mode: BIOS" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
        $CreatePartitionsBIOS = New-TemporaryFile
        @'
Select Disk 0
Clean
Create Partition Primary Size=100
format quick fs=ntfs label="System"
assign letter="A"
active
create partition primary
shrink minimum=750
format quick fs=ntfs label="Windows"
assign letter="C"
create partition primary
format quick fs=ntfs label="Recovery image"
assign letter="R"
set id=27
list volume
exit
'@ | Set-Content $CreatePartitionsBIOS

        $result = Start-Process -FilePath "diskpart.exe" -ArgumentList "/s `"$CreatePartitionsBIOS`"" -Wait -PassThru
        Remove-Item $CreatePartitionsBIOS -Force
        return $result.ExitCode -eq 0
    }
    elseif ($FirmwareType -eq 2) {
        Write-Log -Message "Detected firmware mode: UEFI" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
        $CreatePartitionsUEFI = New-TemporaryFile
        @'
select disk 0
clean
convert gpt
create partition efi size=100
format quick fs=fat32 label="System"
assign letter="A"
create partition msr size=16
create partition primary
shrink minimum=900
format quick fs=ntfs label="Windows"
assign letter="C"
create partition primary
format quick fs=ntfs label="Recovery"
assign letter="R"
set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac"
gpt attributes=0x8000000000000001
list volume
exit
'@ | Set-Content $CreatePartitionsUEFI

        $result = Start-Process -FilePath "diskpart.exe" -ArgumentList "/s `"$CreatePartitionsUEFI`"" -Wait -PassThru
        Remove-Item $CreatePartitionsUEFI -Force
        return $result.ExitCode -eq 0
    }
    return $false
}

function Initialize-WindowsRecovery {
    param(
        [string]$WindowsDrive = "C:"
    )

    try {
        Write-Log -Message "Step 4 - Configure and Hide Recovery Partition" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
        
        # Create Recovery directory structure
        $recoveryPath = "R:\Recovery\WindowsRE"
        New-Item -Path $recoveryPath -ItemType Directory -Force | Out-Null

        # Copy WinRE.wim
        $winRESource = Join-Path $WindowsDrive "Windows\System32\Recovery\WinRE.wim"
        $winREDest = Join-Path $recoveryPath "WinRE.wim"
        Copy-Item -Path $winRESource -Destination $winREDest -Force

        # Configure recovery environment
        $reagentcPath = Join-Path $WindowsDrive "Windows\System32\Reagentc.exe"
        Start-Process -FilePath $reagentcPath -ArgumentList "/Setreimage /Path $recoveryPath /Target $WindowsDrive\Windows" -Wait -NoNewWindow
        Start-Process -FilePath $reagentcPath -ArgumentList "/Info /Target $WindowsDrive\Windows" -Wait -NoNewWindow

        return $true
    }
    catch {
        Write-Log -Message "Failed to configure recovery: $_" -Type Error -LogPath $Script:LogPath -Component "OSDeployment"
        return $false
    }
}

function Start-OSDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$CustomerName = "NOCUSTOMER",
        [Parameter(Mandatory=$false)]
        [string]$OrderNumber = (Get-Date -Format "yyyyMMdd"),
        [Parameter(Mandatory=$false)]
        [hashtable]$ImageSelection,
        [Parameter(Mandatory=$false)]
        [string]$UnattendPath = $Script:UnattendPath
    )

    try {
        # Initialize logging first
        Initialize-Logging
        Write-Log -Message "Starting OS Deployment preparation" -Type Info -Component "OSDeployment"

        # Get AD credentials before starting deployment
        $credentials = Prompt-ForCredentials
        if (-not $credentials) {
            Write-Log -Message "Deployment cancelled - no valid credentials provided" -Type Warning -Component "OSDeployment"
            return $false
        }

        # Set customer-specific log path after authentication
        $Script:LogPath = Set-CustomerLogPath -CustomerName $CustomerName -OrderNumber $OrderNumber
        Write-Log -Message "Deployment started for Customer: $CustomerName, Order: $OrderNumber" -Type Info -Component "OSDeployment"

        # Map required network drives
        foreach ($drive in $config.DriveMappers) {
            New-NetworkDrive -DriveName $drive.DriveLetter -DrivePath $drive.SharePath -Credential $credentials
        }

        # Initialize logging
        $Script:LogPath = Initialize-LogPath -CustomerName $CustomerName -Component "OSDeployment"
        Write-Log -Message "Starting OS Deployment" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"

        # Use provided image selection or show menu
        if (-not $ImageSelection) {
            $ImageSelection = Show-WindowsVersionMenu
            if (-not $ImageSelection) {
                Write-Log -Message "No Windows version selected. Deployment cancelled." -Type Warning -LogPath $Script:LogPath -Component "OSDeployment"
                return $false
            }
        }

        # Extract image info
        $ImagePath = $ImageSelection.Path
        $ImageIndex = $ImageSelection.ImageIndex

        # Verify prerequisites
        if (-not (Test-DeploymentPrerequisites)) {
            throw "Prerequisites check failed"
        }

        Write-Log -Message "Starting OS Deployment process" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
        
        # Check if system is Dell
        $manufacturer = (Get-WmiObject Win32_ComputerSystem).Manufacturer
        if ($manufacturer -like "*Dell*") {
            Write-Log -Message "Dell system detected, loading storage driver..." -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
            try {
                $dellDriverPath = "Y:\Deployment\Drivers\DELL\iaStorVD.inf"  # Updated Dell driver path
                $driverLoadResult = Start-Process -FilePath "X:\Windows\System32\drvload.exe" -ArgumentList $dellDriverPath -NoNewWindow -Wait -PassThru
                if ($driverLoadResult.ExitCode -eq 0) {
                    Write-Log -Message "Dell storage driver loaded successfully" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
                } else {
                    Write-Log -Message "Warning: Dell storage driver load failed with exit code: $($driverLoadResult.ExitCode)" -Type Warning -LogPath $Script:LogPath -Component "OSDeployment"
                }
            }
            catch {
                Write-Log -Message "Warning: Dell storage driver load failed: $_" -Type Warning -LogPath $Script:LogPath -Component "OSDeployment"
            }
        }

        # Check for drivers before disk formatting
        $driverPath = Get-MatchingDriverPath
        if (-not $driverPath) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "No drivers found for this device. Continue without drivers?",
                "Driver Warning",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                Write-Log -Message "Deployment cancelled due to missing drivers." -Type Warning -LogPath $Script:LogPath -Component "OSDeployment"
                return $false
            }
        }

        # Add confirmation before disk formatting
        $confirmMessage = @"
WARNING: This will erase all data on the boot drive.
Selected Image: $ImagePath
Selected Index: $ImageIndex
Driver Status: $(if ($driverPath) {"Drivers Found"} else {"No Drivers"})

Are you sure you want to continue?
"@
        $result = [System.Windows.Forms.MessageBox]::Show(
            $confirmMessage,
            "Confirm Disk Format",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::No) {
            Write-Log -Message "Deployment cancelled by user before disk formatting." -Type Warning -LogPath $Script:LogPath -Component "OSDeployment"
            return $false
        }

        # Initialize disk partitioning
        if (-not (Initialize-DiskPartitioning)) {
            throw "Disk partitioning failed"
        }

        # Apply Windows image
        Write-Log -Message "Step 2 - Applying Image" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
        New-Item -Path C:\ -Name Scratchdir -ItemType Directory -ErrorAction SilentlyContinue

        $dismArgs = if ($ImageType -eq "esd") {
            "/Apply-Image /ImageFile:`"$ImagePath`" /Index:$ImageIndex /ApplyDir:C:\ /ScratchDir:C:\Scratchdir"
        } else {
            "/Apply-Image /ImageFile:`"$ImagePath`" /Index:$ImageIndex /ApplyDir:C:\"
        }

        $dismResult = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -NoNewWindow -Wait -PassThru
        if ($dismResult.ExitCode -ne 0) {
            throw "DISM failed with exit code $($dismResult.ExitCode)"
        }

        if (-not (Test-Path "C:\Windows" -PathType Container)) {
            throw "Windows installation failed - Windows directory not found"
        }

        Write-Log -Message "Step 3 - Configure System Files using BCDBoot" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
        $bcdbootResult = Start-Process -FilePath "C:\Windows\System32\bcdboot.exe" -ArgumentList "C:\Windows /s A:" -Wait -PassThru
        if ($bcdbootResult.ExitCode -ne 0) {
            throw "BCDBoot failed with exit code $($bcdbootResult.ExitCode)"
        }

        # Initialize Windows Recovery
        if (-not (Initialize-WindowsRecovery -WindowsDrive "C:")) {
            Write-Log -Message "Warning: Recovery configuration failed" -Type Warning -LogPath $Script:LogPath -Component "OSDeployment"
        }

        # Add drivers if available
        if ($driverPath) {
            Add-DriversToImage -WindowsDrive "C" -DriverPath $driverPath
        }

        # Apply unattend if specified
        if (Test-Path $UnattendPath) {
            Write-Log -Message "Applying unattend.xml..." -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
            Copy-Item -Path $UnattendPath -Destination "C:\Windows\Panther\unattend.xml"
        }

        Remove-Item -Path "C:\Scratchdir" -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log -Message "OS Deployment completed successfully" -Type Info -LogPath $Script:LogPath -Component "OSDeployment"
        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Deployment failed: $_",
            "OS Deployment Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        Write-Log -Message "Deployment failed: $_" -Type Error -LogPath $Script:LogPath -Component "OSDeployment"
        return $false
    }
}

# Export module members - Remove Show-WindowsVersionMenu since it's now in DeploymentMenu
Export-ModuleMember -Function @(
    'Start-OSDeployment',
    'Test-DeploymentPrerequisites'
) -Variable @(
    'LogBasePath',
    'Windows10Path',
    'Windows11Path',
    'UnattendPath',
    'CustomersPath',
    'DriverBasePath'
)
