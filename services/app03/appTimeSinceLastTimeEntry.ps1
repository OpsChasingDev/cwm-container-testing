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
}

# Import ConnectWiseManageAPI module from PowerShell Gallery
if (-not (Get-Module -ListAvailable -Name ConnectWiseManageAPI)) {
    try {
        Install-Module -Name ConnectWiseManageAPI -Scope CurrentUser -Force -AllowClobber
        New-CWMLog -Type "Info" -Message "ConnectWiseManageAPI module installed successfully"
    }
    catch {
        New-CWMLog -Type "Error" -Message "Failed to install ConnectWiseManageAPI module: $($_.Exception.Message)"
    }
}

# Initialize the application with data path and logging setup
$dataPath = Initialize-CWMApp -AppName $script:appName
New-CWMLog -Type "Info" -Message "Starting $script:appName service"
New-CWMLog -Type "Info" -Message "Data path: $dataPath"

# Connect to ConnectWise Manage API
# $Connection = @{
#     Server = $env:CWM_Server
#     Company = $env:CWM_Company
#     PubKey = $env:CWM_PublicKey
#     PrivateKey = $env:CWM_PrivateKey
#     ClientId = $env:CWM_ClientID
# }
try {
    Connect-CWMAPI
    New-CWMLog -Type "Info" -Message "Connected to ConnectWise Manage API at $($env:CWM_Server)"
}
catch {
    New-CWMLog -Type "Error" -Message "Failed to connect to ConnectWise Manage API: $($_.Exception.Message)"
}

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
    # test running Get-CWMTicket -id 1111111 to ensure API connectivity
    # try {
    #     $testTicket = Get-CWMTicket -id 1111111
    #     New-CWMLog -Type "Info" -Message "API connectivity test successful"
    # }
    # catch {
    #     New-CWMLog -Type "Error" -Message "API connectivity test failed: $($_.Exception.Message)"
    # }
    Start-Sleep -Seconds 10
}