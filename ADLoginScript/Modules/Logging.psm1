Import-Module "$PSScriptRoot\DeploymentConfig.psm1"
Import-Module "$PSScriptRoot\WinPEUtil.psm1"

# Initialize logging variables
$Script:DefaultLogPath = $null
$Script:CurrentLogPath = $null
$Script:SerialNumber = $null
$Script:HasCustomerInfo = $false

function Initialize-Logging {
    $config = Get-DeploymentConfig
    
    # Handle WinPE environment
    if (Test-WinPE) {
        $Script:SerialNumber = (Get-WmiObject Win32_BIOS).SerialNumber
        if (-not $Script:SerialNumber) { 
            $Script:SerialNumber = "Unknown-$(Get-Date -Format 'yyyyMMdd-HHmmss')" 
        }
        
        # Use X: drive for temporary logging until network is available
        $tempLogPath = Join-Path (Get-WinPETempPath) "DeploymentLogs"
        $Script:DefaultLogPath = Join-Path $tempLogPath "$($Script:SerialNumber)\Deployment.log"
        
        # Create temp log directory
        if (-not (Test-Path $tempLogPath)) {
            New-Item -Path $tempLogPath -ItemType Directory -Force | Out-Null
        }
    }
    else {
        $Script:SerialNumber = (Get-WmiObject Win32_BIOS).SerialNumber
        if (-not $Script:SerialNumber) { $Script:SerialNumber = "Unknown-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }

        # Set default log path for pre-deployment logging
        $Script:DefaultLogPath = "\\$($config.ServerName)\Logs\DeploymentLogs\$($Script:SerialNumber)\Deployment.log"
        
        # Ensure log directory exists
        $logDir = Split-Path $Script:DefaultLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
    }

    $Script:CurrentLogPath = $Script:DefaultLogPath
    Write-Log -Message "Logging initialized for device $Script:SerialNumber in $(if (Test-WinPE) {'WinPE'} else {'Windows'}) environment" -Type Info -Component "Logging"
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Type = 'Info',
        
        [Parameter(Mandatory=$false)]
        [string]$Component = 'General',
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath
    )
    
    try {
        # Initialize logging if needed
        if (-not $Script:CurrentLogPath) {
            Initialize-Logging
        }

        # Use provided log path or current path
        $targetLogPath = if ($LogPath) { $LogPath } else { $Script:CurrentLogPath }
        
        # Ensure log directory exists
        $logDir = Split-Path $targetLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }

        # Create timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Format log entry
        $logEntry = "[$timestamp] [$Type] [$Component] - $Message"
        
        # Write to log file
        Add-Content -Path $targetLogPath -Value $logEntry -Force

        # Also write to console with color coding
        $color = switch ($Type) {
            'Info'    { 'White' }
            'Warning' { 'Yellow' }
            'Error'   { 'Red' }
            'Debug'   { 'Cyan' }
            default   { 'White' }
        }
        
        Write-Host $logEntry -ForegroundColor $color
    }
    catch {
        Write-Host "Failed to write to log: $_" -ForegroundColor Red
    }
}

function Set-CustomerLogPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CustomerName,
        
        [Parameter(Mandatory=$true)]
        [string]$OrderNumber
    )

    $config = Get-DeploymentConfig
    
    # Update log path to customer-specific location
    $Script:CurrentLogPath = "\\$($config.ServerName)\Logs\$CustomerName\$OrderNumber\$($Script:SerialNumber)\Deployment.log"
    $Script:HasCustomerInfo = $true
    
    # Create new log directory
    $logDir = Split-Path $Script:CurrentLogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Move existing logs to new location
    if (Test-Path $Script:DefaultLogPath) {
        # Create a compressed backup of pre-customer logs
        $backupPath = "\\$($config.ServerName)\Logs\DeploymentLogs\$($Script:SerialNumber)"
        $backupFile = Join-Path $backupPath "PreCustomer_$(Get-Date -Format 'yyyyMMddHHmmss').zip"
        
        try {
            Compress-Archive -Path $Script:DefaultLogPath -DestinationPath $backupFile -Force
            Copy-Item -Path $Script:DefaultLogPath -Destination $Script:CurrentLogPath -Force
            Write-Log -Message "Previous logs archived to $backupFile and transferred to customer-specific location" -Type Info -Component "Logging"
        }
        catch {
            Write-Log -Message "Warning: Failed to archive previous logs: $_" -Type Warning -Component "Logging"
        }
    }

    Write-Log -Message "Log path updated for Customer: $CustomerName, Order: $OrderNumber" -Type Info -Component "Logging"
    return $Script:CurrentLogPath
}

function Get-CurrentLogPath {
    if (-not $Script:CurrentLogPath) {
        Initialize-Logging
    }
    return $Script:CurrentLogPath
}

Export-ModuleMember -Function Write-Log, Initialize-Logging, Set-CustomerLogPath, Get-CurrentLogPath
