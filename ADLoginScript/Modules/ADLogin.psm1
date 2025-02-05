Import-Module "$PSScriptRoot\DeploymentConfig.psm1"

function Test-ADCredentials {
    param (
        [string]$Username,
        [string]$Password
    )

    $config = Get-DeploymentConfig
    $domain = $config.ADDomain
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

    Write-Host "Testing AD credentials for user: $Username"
    
    try {
        $ldap = "LDAP://$domain"
        $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldap, $Username, $Password)
        
        # Test the connection
        $null = $directoryEntry.NativeObject
        Write-Host "Credentials validated successfully." -ForegroundColor Green
        return $true
    } 
    catch {
        Write-Host "Failed to validate credentials: $_" -ForegroundColor Red
        return $false
    }
}

function Prompt-ForCredentials {
    $valid = $false
    $credential = $null
    
    while (-not $valid) {
        Write-Host "`nPlease enter your Active Directory credentials:" -ForegroundColor Cyan
        $credential = Get-Credential -Message "Enter domain credentials"
        
        if (-not $credential) {
            Write-Host "Credential entry cancelled by user." -ForegroundColor Red
            return $null
        }

        $valid = Test-ADCredentials -Username $credential.UserName -Password $credential.GetNetworkCredential().Password
        
        if (-not $valid) {
            Write-Host "Invalid credentials. Please try again." -ForegroundColor Red
        }
    }
    
    return $credential
}

Export-ModuleMember -Function Test-ADCredentials, Prompt-ForCredentials