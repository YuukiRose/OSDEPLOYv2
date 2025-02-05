Import-Module "$PSScriptRoot\WinPEUtil.psm1"

function New-NetworkDrive {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DriveName,
        
        [Parameter(Mandatory=$true)]
        [string]$DrivePath,
        
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$Credential
    )

    try {
        # Initialize WinPE network if needed
        if (Test-WinPE) {
            if (-not (Initialize-WinPENetwork)) {
                throw "Failed to initialize WinPE network"
            }
        }

        # Use net use for WinPE, PSDrive for regular Windows
        if (Test-WinPE) {
            $driveMapping = "${DriveName}:"
            # Remove existing mapping
            net use $driveMapping /delete /y 2>$null
            
            # Create new mapping
            $username = $Credential.UserName
            $password = $Credential.GetNetworkCredential().Password
            $result = net use $driveMapping $DrivePath /user:$username $password /persistent:no
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to map drive: $result"
            }
        }
        else {
            # Remove existing PSDrive if it exists
            if (Get-PSDrive -Name $DriveName -ErrorAction SilentlyContinue) {
                Remove-PSDrive -Name $DriveName -Force -ErrorAction SilentlyContinue
            }

            # Remove existing network drive mapping using net use
            $driveMapping = "$($DriveName):"
            $existingMapping = net use $driveMapping 2>&1
            if ($LASTEXITCODE -eq 0 -or $existingMapping -like "*remembered*") {
                Write-Host "Removing existing mapping for drive $driveMapping" -ForegroundColor Yellow
                net use $driveMapping /delete /y
                Start-Sleep -Seconds 1
            }

            # Clear any cached credentials from registry
            $networkPath = "HKCU:\Network\$DriveName"
            if (Test-Path $networkPath) {
                try {
                    Remove-Item -Path $networkPath -Force -ErrorAction SilentlyContinue
                    Write-Host "Cleared cached credentials for $DriveName" -ForegroundColor Yellow
                }
                catch {
                    Write-Host "Unable to clear cached credentials: $_" -ForegroundColor Yellow
                }
            }

            # Create new persistent drive
            Write-Host "Mapping drive $DriveName to $DrivePath..." -ForegroundColor Yellow
            New-PSDrive -Name $DriveName -PSProvider FileSystem -Root $DrivePath -Credential $Credential -Persist -Scope Global -ErrorAction Stop
        }

        # Verify the mapping
        Start-Sleep -Seconds 2
        if (Test-Path "${DriveName}:\") {
            Write-Host "Drive ${DriveName}: mapped successfully to $DrivePath" -ForegroundColor Green
            return $true
        }
        throw "Drive mapping verification failed"
    }
    catch {
        Write-Host "Failed to map drive ${DriveName}: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Export-ModuleMember -Function New-NetworkDrive