$script:appName = "appReopenedTicket"
$FrequencyMinutes = 2

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

# Initialize the application with data path, environment variables, and logging setup
$dataPath = Initialize-CWMApp -AppName $script:appName
$boardsEnv = $env:TICKETING_BOARDS -split ","

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

# Connect to ConnectWise Manage API
try {
    Connect-CWMAPI
    New-CWMLog -Type "Info" -Message "Connected to ConnectWise Manage API at $($env:CWM_Server)"
}
catch {
    New-CWMLog -Type "Error" -Message "Failed to connect to ConnectWise Manage API: $($_.Exception.Message)"
}

#endregion SHARED INTITALIZATION

New-CWMLog -Type "Info" -Message "STARTING $($script:appName.ToUpper()) SERVICE"
while ($true) {
    $Start = Get-Date
    New-CWMLog -Type "Info" -Message "Starting new iteration of $script:appName"

    ##########################
    #region APP SPECIFIC LOGIC
    ##########################

    # INSERT APP LOGIC HERE

    #############################
    #endregion APP SPECIFIC LOGIC
    #############################

    #region App Iteration Handler
    $FrequencyMilliseconds = $FrequencyMinutes * 60 * 1000
    $End = Get-Date
    $OperationTime = ($End - $Start).TotalMilliseconds
    $RemainderDelay = $FrequencyMilliseconds - $OperationTime
    if ($RemainderDelay -gt 0) {
        New-CWMLog -Type "Info" -Message "Iteration completed in $([math]::Round($OperationTime / 1000, 2)) seconds. Sleeping for $([math]::Round($RemainderDelay / 1000, 2)) seconds."
        Start-Sleep -Milliseconds $RemainderDelay
    }
    else {
        New-CWMLog -Type "Warning" -Message "Iteration took longer ($([math]::Round($OperationTime / 1000, 2)) seconds) than the configured frequency of $FrequencyMinutes minutes. Starting next iteration immediately."
    }
    #endregion App Iteration Handler
}
