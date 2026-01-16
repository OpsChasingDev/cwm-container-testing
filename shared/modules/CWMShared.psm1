function New-CWMLog {
    <#
    .SYNOPSIS
    Creates a formatted log entry with timestamp, type, and message.

    .DESCRIPTION
    Outputs a standardized log entry to Write-Host in the format: 
    "MM/dd/yyyy HH:mm:ss || TYPE || Message"

    .PARAMETER Type
    The log level type. Must be one of: "Info", "Warning", or "Error"

    .PARAMETER Message
    The log message text.

    .EXAMPLE
    New-CWMLog -Type "Info" -Message "Starting script"
    Output: 02/08/2023 19:42:44 || INFO || Starting script

    .EXAMPLE
    New-CWMLog -Type "Error" -Message "Failed to connect to API"
    Output: 02/08/2023 19:42:45 || ERROR || Failed to connect to API
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Type,
        
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    $typeUppercase = $Type.ToUpper()
    $logEntry = "$timestamp || $typeUppercase || $Message"
    
    Write-Host $logEntry
}

function Initialize-CWMApp {
    <#
    .SYNOPSIS
    Initializes a CWM application with data path and logging.

    .DESCRIPTION
    Sets up the data directory for the application, creates it if it doesn't exist,
    and logs the initialization. This function should be called at the start of
    every CWM application script to ensure consistent setup.

    .PARAMETER AppName
    The name of the application. Used to create the app-specific data directory
    at /mnt/cwm-data/<AppName>

    .EXAMPLE
    $dataPath = Initialize-CWMApp -AppName "app1"
    Output: 01/16/2026 14:30:45 || INFO || Initializing app: app1
            01/16/2026 14:30:45 || INFO || Data path: /mnt/cwm-data/app1
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    
    $script:dataPath = "/mnt/cwm-data/$AppName"
    
    # Create data directory if it doesn't exist
    if (-not (Test-Path $script:dataPath)) {
        try {
            New-Item -ItemType Directory -Path $script:dataPath -Force | Out-Null
            New-CWMLog -Type "Info" -Message "Created data directory: $script:dataPath"
        }
        catch {
            New-CWMLog -Type "Error" -Message "Failed to create data directory: $($_.Exception.Message)"
            throw
        }
    }
    
    New-CWMLog -Type "Info" -Message "Initializing app: $AppName"
    New-CWMLog -Type "Info" -Message "Data path: $script:dataPath"
    
    return $script:dataPath
}

# Export the functions
Export-ModuleMember -Function New-CWMLog, Initialize-CWMApp