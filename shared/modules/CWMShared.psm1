#region INITIALIZING Functions
########################################

function New-CWMLog {
    <#
    .SYNOPSIS
    Creates a formatted log entry with timestamp, type, and message.

    .DESCRIPTION
    Outputs a standardized log entry to Write-Host in the format: 
    "MM/dd/yyyy HH:mm:ss || TYPE || Message"
    
    Also writes the same log entry to a log file in the cwm-shared-logging volume
    if the $script:logFilePath variable has been initialized by Initialize-CWMApp.

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
    
    # Write to console
    Write-Host $logEntry
    
    # Write to log file if path is initialized
    if ($script:logFilePath) {
        try {
            Add-Content -Path $script:logFilePath -Value $logEntry -ErrorAction Stop
        }
        catch {
            Write-Host "WARNING: Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

function Initialize-CWMApp {
    <#
    .SYNOPSIS
    Initializes a CWM application with data path, logging path, and logging.

    .DESCRIPTION
    Sets up the data directory for the application and the logging file, creates 
    them if they don't exist, and logs the initialization. This function should be 
    called at the start of every CWM application script to ensure consistent setup.

    .PARAMETER AppName
    The name of the application. Used to create the app-specific data directory
    at /mnt/cwm-data/<AppName> and a timestamped log file at 
    /mnt/cwm-logs/<AppName>_YYYY-MM-DD_HH-mm-ss.log

    .EXAMPLE
    $dataPath = Initialize-CWMApp -AppName "app1"
    Output: 01/16/2026 14:30:45 || INFO || Initializing app: app1
            01/16/2026 14:30:45 || INFO || Data path: /mnt/cwm-data/app1
            01/16/2026 14:30:45 || INFO || Log file: /mnt/cwm-logs/app1_2026-01-16_14-30-45.log
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
            Write-Host "Created data directory: $script:dataPath"
        }
        catch {
            Write-Host "ERROR: Failed to create data directory: $($_.Exception.Message)"
            throw
        }
    }
    
    # Set up logging
    $loggingPath = "/mnt/cwm-logs"
    
    # Create logging directory if it doesn't exist
    if (-not (Test-Path $loggingPath)) {
        try {
            New-Item -ItemType Directory -Path $loggingPath -Force | Out-Null
            Write-Host "Created logging directory: $loggingPath"
        }
        catch {
            Write-Host "ERROR: Failed to create logging directory: $($_.Exception.Message)"
            throw
        }
    }
    
    # Create log file with timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $script:logFilePath = "$loggingPath/${AppName}_${timestamp}.log"
    
    # Create the log file
    try {
        New-Item -ItemType File -Path $script:logFilePath -Force | Out-Null
    }
    catch {
        Write-Host "ERROR: Failed to create log file: $($_.Exception.Message)"
        $script:logFilePath = $null
        throw
    }
    
    # Now use New-CWMLog for all subsequent messages
    New-CWMLog -Type "Info" -Message "Initializing app: $AppName"
    New-CWMLog -Type "Info" -Message "Data path: $script:dataPath"
    New-CWMLog -Type "Info" -Message "Log file: $script:logFilePath"
    
    return $script:dataPath
}

function Connect-CWMAPI {
    $Connection = @{
        Server     = $env:CWM_Server
        Company    = $env:CWM_Company
        PubKey     = $env:CWM_PublicKey
        PrivateKey = $env:CWM_PrivateKey
        ClientId   = $env:CWM_ClientID
    }
    try {
        $api = Connect-CWM @Connection
        New-CWMLog -Type "Info" -Message "ConnectWise Manage API connection successful"
        return $api
    }
    catch {
        New-CWMLog -Type "Error" -Message "Failed to connect to ConnectWise Manage API: $($_.Exception.Message)"
        throw
    }
}

########################################
#endregion INITIALIZING Functions

#region HELPER Functions
########################################

function Connect-CWMAPIUnitTest {
    # ensure the presence of ConnectWiseManageAPI module
    Import-Module 'ConnectWiseManageAPI' -Force -ErrorAction SilentlyContinue
    $ModuleCheck = Get-Module -Name 'ConnectWiseManageAPI'
    if (!$ModuleCheck) {
        do {
            $Confirm = Read-Host "You do not have the ConnectWiseManageAPI PowerShell module installed or imported.  Would you like to do so now? (y/n)"
            if ($Confirm -eq 'y') {
                Install-Module ConnectWiseManageAPI -Force
                Import-Module ConnectWiseManageAPI -Force
            }
            elseif ($Confirm -eq 'n') {
                return
            }
        } while ($Confirm -ne 'y' -and $Confirm -ne 'n')
    }
    
    # private server info
    $server = Read-Host "Enter ConnectWise Manage server"
    $company = Read-Host "Enter ConnectWise Manage company name"
    $public_key = Read-Host "Enter public key (secure)" -MaskInput
    $private_key = Read-Host "Enter private key (secure)" -MaskInput
    $client_id = Read-Host "Enter ClientId (secure)" -MaskInput
    
    # connection info setup
    $Connection = @{
        Server = $server
        Company = $company
        PubKey = $public_key
        PrivateKey = $private_key
        ClientId = $client_id
    }
    
    # connection confirmation
    $ConnectionConfirm = Read-Host "Confirm you want to connect (y/n)"
    if ($ConnectionConfirm -eq 'y') {
        Connect-CWM @Connection -Verbose
    }
    else {
        Write-Host "No connection made."
    }
    
    # remove connection setup info from memory
    Remove-Variable Connection -Force -ErrorAction SilentlyContinue
    Remove-Variable server -Force -ErrorAction SilentlyContinue
    Remove-Variable company -Force -ErrorAction SilentlyContinue
    Remove-Variable public_key -Force -ErrorAction SilentlyContinue
    Remove-Variable private_key -Force -ErrorAction SilentlyContinue
    Remove-Variable client_id -Force -ErrorAction SilentlyContinue
}

function Get-CWMTimeSinceLastTimeEntry {
    <#
    .SYNOPSIS
        Proivdes the number of hours since the last time entry was made on a ticket.
    .DESCRIPTION
        Proivdes the number of hours since the last time entry was made on a ticket.
    .EXAMPLE
        Get-CWMTimeSinceLastTimeEntry -TicketID 1131626 -Verbose

        Output:
VERBOSE: Current day/time is 05/10/2023 08:20:57
VERBOSE: Lastest time entry is 05/09/2023 14:39:11
17.7
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline)]
        [int]$TicketID,

        [int]$UTCTimeZone = -5
    )

    BEGIN {
        $CurrentDateTime = Get-Date
    }

    PROCESS {
        ## get the datetime of the last time entry in the ticket
        $LatestTimeEntryDateTime = Get-CWMTimeEntry -condition "(chargeToType='ServiceTicket' OR chargeToType='ProjectTicket') AND chargeToId=$TicketID" -all
        if ($LatestTimeEntryDateTime.count -gt 1) {
            $LatestTimeEntryDateTime = $LatestTimeEntryDateTime[-1].dateEntered
        }
        elseif ($LatestTimeEntryDateTime.count -eq 0) {
            return $null
        }
        else {
            $LatestTimeEntryDateTime = $LatestTimeEntryDateTime.dateEntered
        }
        $LatestTimeEntryDateTime = $LatestTimeEntryDateTime.AddHours($UTCTimeZone)

        Write-Verbose "Current day/time is $CurrentDateTime"
        Write-Verbose "Lastest time entry is $LatestTimeEntryDateTime"

        $Difference = [math]::Round((($CurrentDateTime - $LatestTimeEntryDateTime).TotalHours), 0)
        Write-Output $Difference
    }

    END {}
}

########################################
#endregion HELPER Functions

#region APP Functions
########################################

function New-CWMTimeSinceLastTimeEntryReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline)]
        [int]$TicketID,

        [ValidatePattern('([0-9]|[A-Z])\.csv$')]
        [Parameter(HelpMessage = "Enter a full file path and name ending in .csv")]
        [string]$CSVPath = (Get-Location).Path + "\CWMTimeSinceLastTimeEntryReport.csv",

        [ValidatePattern('([0-9]|[A-Z])\.html$')]
        [Parameter(HelpMessage = "Enter a full file path and name ending in .html")]
        [string]$HTMLPath = (Get-Location).Path + "\CWMTimeSinceLastTimeEntryReport.html",

        [int]$ItemsToDisplay = 20,

        [int]$TotalItems,

        [int]$UTCTimeZone = -5
    )
    
    BEGIN {
        $Today = Get-Date
        $ItemIteration = 0
        $ObjCollection = @()
    }

    PROCESS {
        $ItemIteration++

        $LastTimeEntry = Get-CWMTimeSinceLastTimeEntry -TicketID $TicketID
        if ($LastTimeEntry) {
            $BaseStat = Get-CWMTicket -id $TicketID
            $TicketAge = ($Today - ($BaseStat._info.dateEntered).AddHours($UTCTimeZone)).Days

            $obj = [PSCustomObject]@{
                TicketID             = $BaseStat.id
                Company              = $BaseStat.company.name
                Contact              = $BaseStat.contact.name
                DaysSinceTimeEntered = [math]::Round(($LastTimeEntry / 24), 0) ## property specific to this report
                Board                = $BaseStat.board.name
                Summary              = $BaseStat.summary
                Status               = $BaseStat.status.name
                Resource             = $BaseStat.resources
                Priority             = $BaseStat.priority.name
                TicketAge            = $TicketAge
                DateEntered          = $BaseStat._info.dateEntered.ToShortDateString()
            }

            $ObjCollection += $obj
        }

        if ($TotalItems -and $ItemIteration -le $TotalItems) {
            Write-Progress -Activity "Analyzing tickets..." -Status "$([math]::Round((($ItemIteration/$TotalItems)*100),2))%" -PercentComplete (($ItemIteration / $TotalItems) * 100)
        }
    }

    END {
        $ObjCollection | Sort-Object -Property DaysSinceTimeEntered -Descending | Select-Object -First $ItemsToDisplay | Export-Csv -Path $CSVPath -NoTypeInformation -Force
        $ObjCollection | Sort-Object -Property DaysSinceTimeEntered -Descending | Select-Object -First $ItemsToDisplay | ConvertTo-Html -CssUri reportstyle.css | Out-File -FilePath $HTMLPath -Force
    }
}

########################################
#endregion APP Functions