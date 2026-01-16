$script:appName = "appTimeSinceLastTimeEntry"

#region SHARED INTITALIZATION

# Import shared modules
$modulePath = "/opt/cwm-app/modules/CWMShared.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    New-CWMLog -Type "Info" -Message "CWMShared module imported successfully"
}
else {
    Write-Host "ERROR: CWMShared module not found at $modulePath"
    exit 1
}

# Import ConnectWiseManageAPI module from PowerShell Gallery
if (-not (Get-Module -ListAvailable -Name ConnectWiseManageAPI)) {
    try {
        Install-Module -Name ConnectWiseManageAPI -Scope CurrentUser -Force -AllowClobber
        New-CWMLog -Type "Info" -Message "ConnectWiseManageAPI module installed successfully"
    }
    catch {
        New-CWMLog -Type "Error" -Message "Failed to install ConnectWiseManageAPI module: $($_.Exception.Message)"
        exit 1
    }
}

# Initialize the application with data path and logging setup
$dataPath = Initialize-CWMApp -AppName $script:appName
New-CWMLog -Type "Info" -Message "Starting $script:appName service"
New-CWMLog -Type "Info" -Message "Data path: $dataPath"

# Connect to ConnectWise Manage API
Connect-CWMAPI

#endregion SHARED INTITALIZATION

# Main loop

#check every 10 seconds to ensure the data path is accessible and log accordingly
while ($true) { 
    New-CWMLog -Type "Info" -Message "Service is running normally"
    if (Test-Path $dataPath) {
        New-CWMLog -Type "Info" -Message "Data path is accessible: $dataPath"
    } else {
        New-CWMLog -Type "Error" -Message "Data path is not accessible: $dataPath"
    }
    Start-Sleep -Seconds 10
}