Import-Module "$PSScriptRoot\DeploymentConfig.psm1"

# Add path configuration at the top of the module
$Script:OSDeploymentPath = "X:\Windows\System32\OSDEPLOY\OSDeployment\OSDeployment.psm1"

function Start-WindowsDeployment {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ImagePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("wim", "esd")]
        [string]$ImageType,
        
        [Parameter(Mandatory=$true)]
        [int]$ImageIndex,
        
        [Parameter(Mandatory=$true)]
        [string]$WindowsVersion,

        [Parameter(Mandatory=$false)]
        [string]$CustomerName = "SHI",

        [Parameter(Mandatory=$false)]
        [string]$OrderNumber = "NO ORDER"
    )

    try {
        # Validate parameters
        if (-not (Test-Path $ImagePath)) {
            throw "Image file not found: $ImagePath"
        }

        # Show deployment confirmation
        $confirmMessage = @"
Windows Deployment Configuration:
--------------------------------
Windows Version: $WindowsVersion
Edition: $(if ($ImageIndex -eq 3) {"Professional"} else {"Enterprise"})
Image Path: $ImagePath
Image Type: $ImageType
Image Index: $ImageIndex
Customer Name: $CustomerName
Order Number: $OrderNumber

Do you want to proceed with deployment?
"@

        $result = [System.Windows.Forms.MessageBox]::Show(
            $confirmMessage,
            "Confirm Deployment",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::No) {
            return $false
        }

        # Import OSDeployment module using full path
        if (-not (Test-Path $Script:OSDeploymentPath)) {
            throw "OSDeployment module not found at: $Script:OSDeploymentPath"
        }

        Import-Module $Script:OSDeploymentPath -Force
        
        # Create deployment parameters
        $deploymentParams = @{
            ImagePath = $ImagePath
            ImageType = $ImageType
            ImageIndex = $ImageIndex
            CustomerName = $CustomerName
            OrderNumber = $OrderNumber
        }

        # Start deployment
        $success = Start-OSDeployment @deploymentParams

        if ($success) {
            [System.Windows.Forms.MessageBox]::Show(
                "Windows deployment completed successfully!",
                "Deployment Complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return $true
        }
        return $false
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Deployment failed: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }
}

Export-ModuleMember -Function Start-WindowsDeployment
