Import-Module "$PSScriptRoot\DeploymentConfig.psm1"

# Add helper function at the top
function Test-WindowsImage {
    param([string]$FolderPath)
    $wimPath = Join-Path $FolderPath "install.wim"
    $esdPath = Join-Path $FolderPath "install.esd"
    return (Test-Path $wimPath) -or (Test-Path $esdPath)
}

function Get-WindowsImagePath {
    param([string]$FolderPath)
    $wimPath = Join-Path $FolderPath "install.wim"
    $esdPath = Join-Path $FolderPath "install.esd"
    
    if (Test-Path $wimPath) {
        return @{ Path = $wimPath; Type = "wim" }
    }
    elseif (Test-Path $esdPath) {
        return @{ Path = $esdPath; Type = "esd" }
    }
    return $null
}

function Test-InstallWim {
    param([string]$FolderPath)
    $wimPath = Join-Path $FolderPath "install.wim"
    return Test-Path $wimPath
}

function Show-OSSelectionGUI {
    param (
        [Parameter(Mandatory=$true)]
        [string]$LinuxImagesPath
    )

    # Get server name from config
    $config = Get-DeploymentConfig
    $serverName = $config.ServerName

    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select Operating System"
    $form.Size = New-Object System.Drawing.Size(500, 400)
    $form.StartPosition = "CenterScreen"

    $osLabel = New-Object System.Windows.Forms.Label
    $osLabel.Text = "Select Base OS:"
    $osLabel.Location = New-Object System.Drawing.Point(10, 20)
    $form.Controls.Add($osLabel)

    $osComboBox = New-Object System.Windows.Forms.ComboBox
    $osComboBox.Location = New-Object System.Drawing.Point(10, 50)
    $osComboBox.Items.AddRange([System.Object[]]@("Windows", "Linux"))
    $form.Controls.Add($osComboBox)

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = "Select Version:"
    $versionLabel.Location = New-Object System.Drawing.Point(10, 80)
    $form.Controls.Add($versionLabel)

    $versionComboBox = New-Object System.Windows.Forms.ComboBox
    $versionComboBox.Location = New-Object System.Drawing.Point(10, 110)
    $form.Controls.Add($versionComboBox)

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.Location = New-Object System.Drawing.Point(10, 140)
    $buttonPanel.Size = New-Object System.Drawing.Size(460, 180)
    $buttonPanel.AutoScroll = $true
    $form.Controls.Add($buttonPanel)

    $osComboBox.Add_SelectedIndexChanged({
        $versionComboBox.Items.Clear()
        if ($osComboBox.SelectedItem -eq "Windows") {
            $versionComboBox.Items.AddRange(@("10", "11"))
        } 
        elseif ($osComboBox.SelectedItem -eq "Linux") {
            try {
                $linuxImages = Get-ChildItem -Path $LinuxImagesPath -Directory -ErrorAction Stop
                if ($linuxImages.Count -gt 0) {
                    $versionComboBox.Items.AddRange($linuxImages.Name)
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("No Linux images found in $LinuxImagesPath", "Warning")
                }
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("Error accessing Linux images path: $($_.Exception.Message)", "Error")
            }
        }
        if ($versionComboBox.Items.Count -gt 0) {
            $versionComboBox.SelectedIndex = 0
        }
    })

    $versionComboBox.Add_SelectedIndexChanged({
        $buttonPanel.Controls.Clear()
        if ($osComboBox.SelectedItem -eq "Windows") {
            try {
                $windowsVersion = $versionComboBox.SelectedItem
                $versionsPath = "\\$serverName\Images\Windows\$windowsVersion"
                $versionFolders = Get-ChildItem -Path $versionsPath -Directory -ErrorAction Stop | 
                    Where-Object { Test-WindowsImage -FolderPath $_.FullName }
                
                foreach ($folder in $versionFolders) {
                    $button = New-Object System.Windows.Forms.Button
                    $imageInfo = Get-WindowsImagePath -FolderPath $folder.FullName
                    $button.Text = $folder.Name
                    $button.Width = 200
                    $button.Height = 30
                    
                    # Store both path and type in Tag
                    $button.Tag = $imageInfo
                    
                    $button.Add_Click({
                        $selectedVersion = $this.Text
                        $selectedImage = $this.Tag
                        $windowsVersion = $versionComboBox.SelectedItem
                        
                        if ($selectedImage) {
                            Write-Host "Debug - Image Path: $($selectedImage.Path)"  # Add debug output
                            Write-Host "Debug - Image Type: $($selectedImage.Type)"  # Add debug output
                            
                            # Call Show-WindowsEditionDialog and store result directly as integer
                            [int]$editionIndex = Show-WindowsEditionDialog
                            Write-Host "Debug - Edition Index: $editionIndex"  # Add debug output
                            
                            if ($editionIndex -gt 0) {
                                $customerInfo = Show-CustomerInfoDialog
                                
                                if ($customerInfo) {
                                    Import-Module "$PSScriptRoot\WindowsDeployment.psm1" -Force
                                    $params = @{
                                        ImagePath = $selectedImage.Path
                                        ImageType = $selectedImage.Type
                                        ImageIndex = $editionIndex
                                        WindowsVersion = $windowsVersion
                                        CustomerName = $customerInfo.CustomerName
                                        OrderNumber = $customerInfo.OrderNumber
                                    }
                                    Write-Host "Debug - Deployment Parameters:" # Add debug output
                                    $params | Format-Table | Out-String | Write-Host
                                    
                                    Start-WindowsDeployment @params
                                }
                            }
                        } else {
                            Write-Host "Debug - Selected Image is null!"  # Add debug output
                        }
                        $form.Close()
                    })
                    $buttonPanel.Controls.Add($button)
                }
                
                if ($versionFolders.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show(
                        "No valid Windows $windowsVersion versions found with install.wim in $versionsPath",
                        "Warning"
                    )
                }
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Error accessing Windows versions: $($_.Exception.Message)",
                    "Error"
                )
            }
        }
    })

    $submitButton = New-Object System.Windows.Forms.Button
    $submitButton.Text = "Submit"
    $submitButton.Location = New-Object System.Drawing.Point(10, 330)
    $submitButton.Add_Click({
        $selectedOS = $osComboBox.SelectedItem
        $selectedVersion = $versionComboBox.SelectedItem
        [System.Windows.Forms.MessageBox]::Show("Selected OS: $selectedOS`nSelected Version: $selectedVersion")
        $form.Close()
    })
    $form.Controls.Add($submitButton)

    $form.Add_Shown({$form.Activate()})
    [void]$form.ShowDialog()
}

function Show-WindowsEditionDialog {
    param([string]$WimPath)
    
    # Initialize with explicit integer type
    [int]$script:selectedIndex = 0
    
    $editionForm = New-Object System.Windows.Forms.Form
    $editionForm.Text = "Select Windows Edition"
    $editionForm.Size = New-Object System.Drawing.Size(300, 150)
    $editionForm.StartPosition = "CenterScreen"
    
    $proButton = New-Object System.Windows.Forms.Button
    $proButton.Location = New-Object System.Drawing.Point(50, 20)
    $proButton.Size = New-Object System.Drawing.Size(200, 30)
    $proButton.Text = "Professional"
    $proButton.Add_Click({
        $script:selectedIndex = 5
        $editionForm.Close()
    })
    
    $enterpriseButton = New-Object System.Windows.Forms.Button
    $enterpriseButton.Location = New-Object System.Drawing.Point(50, 60)
    $enterpriseButton.Size = New-Object System.Drawing.Size(200, 30)
    $enterpriseButton.Text = "Enterprise"
    $enterpriseButton.Add_Click({
        $script:selectedIndex = 3
        $editionForm.Close()
    })
    
    $editionForm.Controls.AddRange(@($proButton, $enterpriseButton))
    $editionForm.ShowDialog()
    
    Write-Host "Debug - Returning Index: $script:selectedIndex"  # Add debug output
    return $script:selectedIndex  # Return the integer value
}

function Show-CustomerInfoDialog {
    $customerForm = New-Object System.Windows.Forms.Form
    $customerForm.Text = "Enter Customer Information"
    $customerForm.Size = New-Object System.Drawing.Size(400, 250)
    $customerForm.StartPosition = "CenterScreen"
    
    # Customer Name Label and TextBox
    $customerLabel = New-Object System.Windows.Forms.Label
    $customerLabel.Location = New-Object System.Drawing.Point(20, 20)
    $customerLabel.Size = New-Object System.Drawing.Size(120, 20)
    $customerLabel.Text = "Customer Name:"
    $customerForm.Controls.Add($customerLabel)
    
    $customerTextBox = New-Object System.Windows.Forms.TextBox
    $customerTextBox.Location = New-Object System.Drawing.Point(20, 40)
    $customerTextBox.Size = New-Object System.Drawing.Size(340, 20)
    $customerForm.Controls.Add($customerTextBox)
    
    # Order Number Label and TextBox
    $orderLabel = New-Object System.Windows.Forms.Label
    $orderLabel.Location = New-Object System.Drawing.Point(20, 70)
    $orderLabel.Size = New-Object System.Drawing.Size(120, 20)
    $orderLabel.Text = "Order Number:"
    $customerForm.Controls.Add($orderLabel)
    
    $orderTextBox = New-Object System.Windows.Forms.TextBox
    $orderTextBox.Location = New-Object System.Drawing.Point(20, 90)
    $orderTextBox.Size = New-Object System.Drawing.Size(340, 20)
    $customerForm.Controls.Add($orderTextBox)
    
    # Submit Button
    $submitButton = New-Object System.Windows.Forms.Button
    $submitButton.Location = New-Object System.Drawing.Point(20, 130)
    $submitButton.Size = New-Object System.Drawing.Size(160, 30)
    $submitButton.Text = "Submit Information"
    $submitButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($customerTextBox.Text) -or [string]::IsNullOrWhiteSpace($orderTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please fill in both fields.", "Validation Error")
            return
        }
        $script:customerInfo = @{
            CustomerName = $customerTextBox.Text
            OrderNumber = $orderTextBox.Text
        }
        $customerForm.Close()
    })
    $customerForm.Controls.Add($submitButton)
    
    # Default Button
    $defaultButton = New-Object System.Windows.Forms.Button
    $defaultButton.Location = New-Object System.Drawing.Point(200, 130)
    $defaultButton.Size = New-Object System.Drawing.Size(160, 30)
    $defaultButton.Text = "Use Default Info"
    $defaultButton.Add_Click({
        $script:customerInfo = @{
            CustomerName = "SHI"
            OrderNumber = "NO ORDER"
        }
        $customerForm.Close()
    })
    $customerForm.Controls.Add($defaultButton)
    
    $customerForm.ShowDialog()
    return $script:customerInfo
}

Export-ModuleMember -Function Show-OSSelectionGUI