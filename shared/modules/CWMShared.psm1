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

# Export the function
Export-ModuleMember -Function New-CWMLog