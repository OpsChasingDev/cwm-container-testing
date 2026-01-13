#!/usr/bin/env pwsh

# PowerShell script that creates timestamped files every 5 seconds
Write-Host "Starting file generation script..."
Write-Host "Files will be created in /opt/cwm-app/bin/"

while ($true) {
    # Get current date-time and format it for a filename (avoid characters that are problematic in filenames)
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $filename = "/opt/cwm-app/bin/file_$timestamp.txt"
    
    # Create the file with timestamp content
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "File created at: $currentTime" | Out-File -FilePath $filename -Encoding UTF8
    
    Write-Host "Created file: $filename"
    
    # Wait for 5 seconds before creating the next file
    Start-Sleep -Seconds 5
}
