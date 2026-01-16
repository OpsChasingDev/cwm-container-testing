# AppTimeSinceLastTimeEntry Service Script
# This script calculates and logs the time since the last time entry was written to shared storage

# Import shared modules
$modulePath = "/opt/cwm-app/modules/CWMShared.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}
else {
    Write-Host "ERROR: CWMShared module not found at $modulePath"
    exit 1
}

$appName = "appTimeSinceLastTimeEntry"
$dataPath = "/mnt/cwm-data"

New-CWMLog -Type "Info" -Message "Starting $appName service"
New-CWMLog -Type "Info" -Message "Data path: $dataPath"

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