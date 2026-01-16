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

$appName = "app03"
$dataPath = "/mnt/cwm-data"

New-CWMLog -Type "Info" -Message "Starting $appName service"
New-CWMLog -Type "Info" -Message "Data path: $dataPath"

# Main loop
while ($true) {
    try {
        # Create data directory if it doesn't exist
        if (-not (Test-Path $dataPath)) {
            New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
            New-CWMLog -Type "Info" -Message "Created data directory: $dataPath"
        }

        # Get the most recent file in the shared data directory
        $files = Get-ChildItem -Path $dataPath -File -ErrorAction SilentlyContinue | 
                 Sort-Object LastWriteTime -Descending

        if ($files) {
            $lastFile = $files[0]
            $timeSinceLastEntry = (Get-Date) - $lastFile.LastWriteTime
            
            $logEntry = @{
                Timestamp = (Get-Date -Format 'o')
                LastEntryFile = $lastFile.Name
                LastEntryTime = $lastFile.LastWriteTime
                SecondsSinceLastEntry = [math]::Round($timeSinceLastEntry.TotalSeconds)
                MinutesSinceLastEntry = [math]::Round($timeSinceLastEntry.TotalMinutes, 2)
                HoursSinceLastEntry = [math]::Round($timeSinceLastEntry.TotalHours, 2)
            }

            # Log to console
            New-CWMLog -Type "Info" -Message "Last entry: $($logEntry.LastEntryFile) - $($logEntry.MinutesSinceLastEntry) minutes ago"

            # Write to a status file
            $statusFile = Join-Path $dataPath "appTimeSinceLastTimeEntry-status.json"
            $logEntry | ConvertTo-Json | Out-File $statusFile -Force
        }
        else {
            New-CWMLog -Type "Warning" -Message "No entries found in shared data directory yet"
        }

        # Wait for the next check interval
        Start-Sleep -Seconds 300
    }
    catch {
        New-CWMLog -Type "Error" -Message "Error in $appName service: $_"
        Start-Sleep -Seconds 10
    }
}
