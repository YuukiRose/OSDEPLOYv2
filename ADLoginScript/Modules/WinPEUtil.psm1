function Test-WinPE {
    return Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
}

function Initialize-WinPENetwork {
    if (-not (Test-WinPE)) { return $true }
    
    try {
        Write-Host "Initializing WinPE network components..."
        Start-Process -FilePath "wpeinit.exe" -Wait -NoNewWindow
        
        # Wait for network to be ready
        $timeout = 30
        while ($timeout -gt 0) {
            if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet) {
                Write-Host "Network is ready"
                return $true
            }
            Start-Sleep -Seconds 1
            $timeout--
        }
        throw "Network initialization timed out"
    }
    catch {
        Write-Host "Failed to initialize WinPE network: $_" -ForegroundColor Red
        return $false
    }
}

function Get-WinPETempPath {
    if (Test-WinPE) {
        return "X:\Windows\Temp"
    }
    return $env:TEMP
}

Export-ModuleMember -Function Test-WinPE, Initialize-WinPENetwork, Get-WinPETempPath
