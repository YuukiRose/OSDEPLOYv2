# Set paths
$ADKPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPEPath = "$ADKPath\Windows Preinstallation Environment"
$CopyPE = "C:\WinPE_amd64"
$MountPath = "C:\WinPE_Mount"
$ScriptRoot = "C:\Users\glydr\OneDrive\Desktop\OSDEPLOY\WINPE"
$ADLogonPath = "C:\Users\glydr\OneDrive\Desktop\OSDEPLOY\ADLoginScript"

# Verify ADK Installation
if (-not (Test-Path $ADKPath)) {
    Write-Error "Windows ADK not found. Please install Windows ADK first."
    exit 1
}

# Create working directories
if (Test-Path $CopyPE) { Remove-Item -Path $CopyPE -Recurse -Force }
if (Test-Path $MountPath) { Remove-Item -Path $MountPath -Recurse -Force }
New-Item -Path $MountPath -ItemType Directory -Force | Out-Null

# Use copype.cmd to create WinPE files
Write-Host "Creating WinPE working directory using copype.cmd..."
$currentDir = Get-Location
Set-Location -Path $WinPEPath
& cmd.exe /c "copype.cmd amd64 $CopyPE"
Set-Location -Path $currentDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to execute copype.cmd"
    exit 1
}

# Verify the media directory was created
$mediaPath = "$CopyPE\media"
if (-not (Test-Path $mediaPath)) {
    Write-Error "WinPE media directory was not created at: $mediaPath"
    exit 1
}

# Verify boot.wim exists
$WimFile = "$mediaPath\sources\boot.wim"
if (-not (Test-Path $WimFile)) {
    Write-Error "boot.wim not found at: $WimFile"
    exit 1
}

Mount-WindowsImage -ImagePath $WimFile -Index 1 -Path $MountPath

# Add PowerShell support to WinPE
$WinPEOCs = "$ADKPath\Windows Preinstallation Environment\amd64\WinPE_OCs"
if (Test-Path $WinPEOCs) {
    $packages = @(
        "WinPE-WMI.cab",
        "en-us\WinPE-WMI_en-us.cab",
        "WinPE-NetFX.cab",
        "en-us\WinPE-NetFX_en-us.cab",
        "WinPE-PowerShell.cab",
        "en-us\WinPE-PowerShell_en-us.cab",
        "WinPE-DismCmdlets.cab",
        "en-us\WinPE-DismCmdlets_en-us.cab"
    )

    foreach ($package in $packages) {
        $packagePath = Join-Path $WinPEOCs $package
        if (Test-Path $packagePath) {
            Add-WindowsPackage -Path $MountPath -PackagePath $packagePath
        } else {
            Write-Warning "Package not found: $packagePath"
        }
    }
}

# Create Deploy folder and copy ADLoginScript if it exists
New-Item -Path "$MountPath\Deploy" -ItemType Directory -Force | Out-Null
if (Test-Path $ADLogonPath) {
    Copy-Item -Path $ADLogonPath -Destination "$MountPath\Deploy" -Recurse
} else {
    Write-Warning "ADLoginScript folder not found at $ADLogonPath"
}

# Copy unattend.xml
$unattendPath = Join-Path $ScriptRoot "unattend.xml"
if (Test-Path $unattendPath) {
    New-Item -Path "$MountPath\Windows\System32" -ItemType Directory -Force | Out-Null
    Copy-Item -Path $unattendPath -Destination "$MountPath\Windows\System32"
} else {
    Write-Warning "unattend.xml not found at $unattendPath"
}

# Unmount and save changes
try {
    Dismount-WindowsImage -Path $MountPath -Save
} catch {
    Write-Warning "Error saving WIM file: $_"
    Dismount-WindowsImage -Path $MountPath -Discard
}

# Cleanup
Remove-Item -Path $MountPath -Force -ErrorAction SilentlyContinue
