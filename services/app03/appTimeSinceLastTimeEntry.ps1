#region SHARED INTITALIZATION

$script:appName = "appTimeSinceLastTimeEntry"

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
New-CWMLog -Type "Info" -Message "Starting $script:appName service"
New-CWMLog -Type "Info" -Message "Data path: $dataPath"

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

# Main loop

while ($true) {

    # Retrieve all ticket IDs from specified boards
    try {
        $Id = (Get-CWMFullTicket -Board $boardsEnv -ErrorAction Stop).id
        New-CWMLog -Type "Info" -Message "Retrieved $($Id.Count) tickets from specified boards"
    }
    catch {
        New-CWMLog -Type "Error" -Message "Failed to retrieve tickets: $($_.Exception.Message)"
    }

    # Generate time since last time entry report
    try {
        $Id | New-CWMTimeSinceLastTimeEntryReport `
            -CSVPath "$dataPath/appTimeSinceLastTimeEntry.csv" `
            -HTMLPath "$dataPath/appTimeSinceLastTimeEntry.html" `
            -ItemsToDisplay 1000
        New-CWMLog -Type "Info" -Message "Generated time since last time entry report"
    }
    catch {
        New-CWMLog -Type "Error" -Message "Failed to generate time since last time entry report: $($_.Exception.Message)"
    }

    # Wait for 2 minutes before next iteration
    Start-Sleep -Seconds 120
}