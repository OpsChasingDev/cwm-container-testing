# AppTimeSinceLastTimeEntry Service Script

# High level definitions
$appName = "appTimeSinceLastTimeEntry"
$dataPath = "/mnt/cwm-data"

# Import shared modules
$modulePath = "/opt/cwm-app/modules/CWMShared.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}
else {
    Write-Host "ERROR: CWMShared module not found at $modulePath"
    exit 1
}
# Log startup messages
New-CWMLog -Type "Info" -Message "Starting $appName service"
New-CWMLog -Type "Info" -Message "Data path: $dataPath"

# Main loop
while ($true) {
    # Shows app is running
    New-CWMLog -Type "Info" -Message "Service is running normally"
    # Check if data path is accessible
    if (Test-Path $dataPath) {
        New-CWMLog -Type "Info" -Message "Data path is accessible: $dataPath"
    } else {
        New-CWMLog -Type "Error" -Message "Data path is not accessible: $dataPath"
    }
    Start-Sleep -Seconds 5
}