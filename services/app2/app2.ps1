#!/usr/bin/env pwsh

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

# Initialize the application with data path and logging setup
$appName = "app2"
$dataPath = Initialize-CWMApp -AppName $appName

# PowerShell script that creates timestamped files every 5 seconds
New-CWMLog -Type "Info" -Message "Starting file generation script..."
New-CWMLog -Type "Info" -Message "Files will be created in data path: $dataPath"

while ($true) {
    # Get current date-time and format it for a filename (avoid characters that are problematic in filenames)
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $filename = "$dataPath/file_$timestamp.txt"
    
    # Create the file with timestamp content
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "File created at: $currentTime" | Out-File -FilePath $filename -Encoding UTF8
    
    New-CWMLog -Type "Info" -Message "Created file: $filename"
    
    # Wait for 5 seconds before creating the next file
    Start-Sleep -Seconds 5
}
