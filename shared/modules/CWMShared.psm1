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

function Construct-CWMCondition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Company", "Board", "Resources")]
        [string]$Type,
        
        [Parameter(Mandatory)]
        [string[]]$Value
    )

    # determine the syntax of the key for the query based on -Type
    switch ($Type) {
        Company { $Key = "$($Type.ToLower())/name" }
        Board { $Key = "$($Type.ToLower())/name" }
        Resources { $Key = "resources" }
    }

    # logic for Condition creation
    if ($Value.Count -eq 1) {
        if ($Type -eq "Resources") { $Condition = "($Key like `"*$Value*`")"}
        else { $Condition = "($Key = `"$Value`")" }
    }
    elseif ($Value.Count -gt 1) {
        foreach ($v in $Value) {
            if ($v -eq $Value[0]) {
                if ($Type -eq "Resources") { $Condition = "($Key like `"*$v*`"" }
                else { $Condition = "($Key = `"$v`"" }
                Write-Verbose "Condition is: << $Condition >>"
            }
            elseif ($v -eq $Value[-1]) {
                if ($Type -eq "Resources") { $Condition = $Condition + " OR $Key like `"*$v*`")" }
                else { $Condition = $Condition + " OR $Key = `"$v`")" }
                Write-Verbose "Condition is: << $Condition >>"
            }
            else {
                if ($Type -eq "Resources") { $Condition = $Condition + " OR $Key like `"*$v*`"" }
                else { $Condition = $Condition + " OR $Key = `"$v`"" }
                Write-Verbose "Condition is: << $Condition >>"
            }
        }
    }

    Write-Output $Condition
}

function Get-CWMFullTicket {
    [CmdletBinding(DefaultParameterSetName = "default")]
    param (
        [Parameter(ParameterSetName = "condition",
            Mandatory,
            Position = 1)]
        [string]$Condition,

        [Parameter(ParameterSetName = "default")]
        [string[]]$Company,
        
        [Parameter(ParameterSetName = "default")]
        [string[]]$Board,

        [Parameter(ParameterSetName = "default")]
        [string[]]$Resource,
        
        [Parameter(ParameterSetName = "default")]
        [Parameter(ParameterSetName = "condition",
            Position = 2)]
        [ValidateSet("Closed", "Open", "All")]
        [string]$ClosedStatus = "Open",

        [Parameter(ParameterSetName = "default")]
        [Parameter(ParameterSetName = "condition")]
        [switch]$IncludeChildTicket,

        [Parameter(ParameterSetName = "default")]
        [Parameter(ParameterSetName = "condition")]
        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000
    )

    # safeguard to prevent querying all tickets while in "default" paramset
    if ($PSCmdlet.ParameterSetName -eq "default" -and (!$Company -and !$Board -and !$Resource)) {
        Write-Warning "You must specify a condition-defining parameter in the default parameter set."
        return
    }

    # preparations for entry collection, handling 1000+ result per page by default
    [System.Collections.ArrayList]$ResultCol = @()
    $CurrentPage = 1

    # logic for Resource param
    if ($Resource) {
        $ResourceCondition = Construct-CWMCondition -Type Resources -Value $Resource
        if ($Condition) {
            $Condition = $Condition + " AND " + $ResourceCondition
            Write-Verbose "Condition is: << $Condition >>"
        }
        elseif (!$Condition) {
            $Condition = $ResourceCondition
        }
    }

    # logic for Company param
    if ($Company) {
        $CompanyCondition = Construct-CWMCondition -Type Company -Value $Company
        if ($Condition) {
            $Condition = $Condition + " AND " + $CompanyCondition
            Write-Verbose "Condition is: << $Condition >>"
        }
        elseif (!$Condition) {
            $Condition = $CompanyCondition
        }
    }
    
    # logic for Board param
    if ($Board) {
        $BoardCondition = Construct-CWMCondition -Type Board -Value $Board
        if ($Condition) {
            $Condition = $Condition + " AND " + $BoardCondition
            Write-Verbose "Condition is: << $Condition >>"
        }
        elseif (!$Condition) {
            $Condition = $BoardCondition
        }
    }

    # set parenthesis around -Condition value if in the condition paramset
    if ($PSCmdlet.ParameterSetName -eq "condition") {
        $Condition = $Condition.Insert(0, "(")
        $Condition = $Condition.Insert($Condition.Length, ")")
        Write-Verbose "Condition is: << $Condition >>"
    }

    # logic for ClosedStatus param
    if ($ClosedStatus -eq "Open") {
        $Condition = $Condition.Insert(($Condition.Length), " AND closedFlag = False")
        Write-Verbose "Condition is: << $Condition >>"
    }
    elseif ($ClosedStatus -eq "Closed") {
        $Condition = $Condition.Insert(($Condition.Length), " AND closedFlag = True")
        Write-Verbose "Condition is: << $Condition >>"
    }
    else {}

    # loop to iterate through pages of ticket results until no more exist
    do {
        $ResultCount = 0
        $CWMTicketSplat = @{
            page      = $CurrentPage
            pageSize  = $PageSize
            condition = $Condition
        }
        # adds each ticket to the output collection, by default excludes child tickets
        $null = Get-CWMTicket @CWMTicketSplat |
        ForEach-Object {
            if (!$_.parentTicketId -or $IncludeChildTicket) {
                $ResultCol.Add($_)
            }
            $ResultCount++
        }
        $CurrentPage++
    } while ($ResultCount -eq $PageSize)

    Write-Output $ResultCol
}

function Get-CWMFullAuditTrail {
    <#
    .SYNOPSIS
        Wrapper function for getting all the Ticket type audit trail entries for a ticket.
    .DESCRIPTION
        Wrapper function for getting all the Ticket type audit trail entries for a ticket.
        This function circumnavigates the CWM REST API limitation of 1000 results per query by looping requests of a page size no greater than 1000 until there are no more audit trail entries to return.
        The default page result size is 1000, but can be set no higher.  Best performance will come from leaving this default.
        Results gathered will be returned chronologically in ascending order.
    .NOTES
        You must first be connected to a CWM system in order to use this function.
        Date/time information will be returned in UTC, so adjust results accordingly based on your region and use case.
    .EXAMPLE
        PS C:\git\ConnectWise_Manage> (Get-CWMFullAuditTrail -TicketID 1020834 | select enteredDate).count
2141
        PS C:\git\ConnectWise_Manage> (Measure-Command { (Get-CWMFullAuditTrail -TicketID 1020834).count }).TotalSeconds
1.9232057
        
        The first command returns the number of total audit trail entries for the ticket.
        The second command measures how long it took to run the first command, returned in the total number of seconds elapsed.
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline)]
        [int]$TicketID,

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000
    )

    BEGIN {}

    PROCESS {
        [System.Collections.ArrayList]$ResultCol = @()
        $CurrentPage = 1

        # loop to iterate through pages of audit trail results until no more exist
        do {
            $ResultCount = 0
            $AuditTrailSplat = @{
                id       = $TicketID
                type     = "Ticket"
                page     = $CurrentPage
                pageSize = $PageSize
            }
            $null = Get-CWMAuditTrail @AuditTrailSplat |
            ForEach-Object {
                $ResultCol.Add($_)
                $ResultCount++
            }
            $CurrentPage++
        } while ($ResultCount -eq $PageSize)

        Write-Output $ResultCol
    }
    
    END {}
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

function Get-CWMReopenedTicketStatistics {
    <#
    .SYNOPSIS
        Returns information on a ticket reopening.
    .DESCRIPTION
        Returns information on a ticket reopening.
        The information returned is always from the most recent reopening.
        The script automatically accounts for returning a user for the "ClosedBy" property, meaning that technically the immediate closing status change prior to reopening was a workflow rule, but the closing status change listed will be the last one performed by a human user.
    .EXAMPLE
        PS C:\> Get-CWMReopenedTicketStatistics 1072849

TicketID      : 1072849
TimesReopened : 4
DateClosed    : 12/30/2022 12:52:33 PM
ClosedBy      : Robert Stapleton
DateReopened  : 12/30/2022 12:52:35 PM
OpenedBy      : Robert Stapleton

        Shows that ticket 1072849 has been reopened 4 times, and the detailed information shows the latest of those occurrences.
    .EXAMPLE
        PS C:\> Get-CWMFullTicket -Board "Escalations" | select -ExpandProperty id | Get-CWMReopenedTicketStatistics
        
TicketID      : 1074670
TimesReopened : 1
DateClosed    : 12/27/2022 4:05:04 PM
ClosedBy      : Al Fuller
DateReopened  : 12/27/2022 4:19:26 PM
OpenedBy      : Ric Cisneros

TicketID      : 1074940
TimesReopened : 1
DateClosed    : 12/19/2022 5:19:07 PM
ClosedBy      : Rian Stancil
DateReopened  : 12/21/2022 2:23:00 PM
OpenedBy      : CW Service

        This code looked at every ticket on the Escalations board and returned information about the only two tickets that had ever been reopened.
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline)]
        [int]$TicketID,

        [int]$TotalItems,

        [int]$UTCTimeZone = -5
    )

    BEGIN { $ItemIteration = 0 }

    PROCESS {
        $ItemIteration++

        # object creation
        $ReopenCounter = 0
        $AuditIndex = 0

        # initial information for the board the ticket resides and differentiating closing statuses from opening statuses
        $Ticket = Get-CWMTicket -id $TicketID
        $BoardStatus = Get-CWMBoardStatus -parentId ($Ticket.board.id) | Select-Object name, closedstatus
        $OpenStatus = $BoardStatus | Where-Object { $_.closedStatus -eq $false }
        $ClosedStatus = $BoardStatus | Where-Object { $_.closedStatus -eq $true }
        $AuditTrail = Get-CWMFullAuditTrail -TicketID $TicketID | Where-Object { $_.auditType -eq 'Tickets' -and $_.auditSubType -eq 'Status' } | Sort-Object enteredDate

        foreach ($Audit in $AuditTrail) {
            $AuditIndex++

            $OldStatus = (($Audit.text).Split('"'))[-4]
            $NewStatus = (($Audit.text).Split('"'))[-2]

            if ($ClosedStatus.name -contains $OldStatus -and $OpenStatus.name -contains $NewStatus) {
                
                # accounting for the last closed status change possibly being a workflow rule (like "Completed - Send Survey" to "Automated - Completed - Survey Sent")
                $PriorClosedIndex = 2
                while ($AuditTrail[($AuditIndex - $PriorClosedIndex)].enteredBy -eq "Workflow") {
                    $PriorClosedIndex++
                }
                
                $ReopenCounter++
                $DateClosed = ($AuditTrail[($AuditIndex - $PriorClosedIndex)].enteredDate).AddHours($UTCTimeZone)
                $ClosedBy = $AuditTrail[($AuditIndex - $PriorClosedIndex)].enteredBy
                $DateReopened = ($AuditTrail[($AuditIndex - 1)].enteredDate).AddHours($UTCTimeZone)
                $OpenedBy = $AuditTrail[($AuditIndex - 1)].enteredBy
            }
        }

        if ($ReopenCounter -gt 0) {
            $obj = [PSCustomObject]@{
                TicketID      = $TicketID
                TimesReopened = $ReopenCounter
                DateClosed    = $DateClosed
                ClosedBy      = $ClosedBy
                DateReopened  = $DateReopened
                OpenedBy      = $OpenedBy
            }
            Write-Output $obj
        }
        else { return }

        if ($TotalItems -and $ItemIteration -le $TotalItems) {
            Write-Progress -Activity "Analyzing tickets..." -Status "$([math]::Round((($ItemIteration/$TotalItems)*100),2))%" -PercentComplete (($ItemIteration / $TotalItems) * 100)
        }
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

function New-CWMReopenedTicketReport {
    <#
    .SYNOPSIS
        Generates a CSV and HTML report for re-opened tickets.
    .DESCRIPTION
        Generates a CSV and HTML report for re-opened tickets.  Intended use for BrightGauge.
    .EXAMPLE
        PS C:\> (Get-CWMFullTicket -Board "Team 1","Team 2","Team 3","Escalations","Build Team","Staff Aug").id | New-CWMReopenedTicketReport
        Gets all tickets on the described boards and generates the csv and html reports at the current location.
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline)]
        [int]$TicketID,

        [ValidatePattern('([0-9]|[A-Z])\.csv$')]
        [Parameter(HelpMessage = "Enter a full file path and name ending in .csv")]
        [string]$CSVPath = (Get-Location).Path + "\CWMReopenedTicketReport.csv",

        [ValidatePattern('([0-9]|[A-Z])\.html$')]
        [Parameter(HelpMessage = "Enter a full file path and name ending in .html")]
        [string]$HTMLPath = (Get-Location).Path + "\CWMReopenedTicketReport.html",

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

        $ReopenedStat = Get-CWMReopenedTicketStatistics -TicketID $TicketID
        if ($ReopenedStat.TimesReopened -gt 0) {
            $BaseStat = Get-CWMTicket -id $TicketID
            $TicketAge = ($Today - ($BaseStat._info.dateEntered).AddHours($UTCTimeZone)).Days

            $obj = [PSCustomObject]@{
                TicketID      = $BaseStat.id
                Company       = $BaseStat.company.name
                Contact       = $BaseStat.contact.name
                TimesReopened = $ReopenedStat.TimesReopened ## property specific to this report
                DateClosed    = $ReopenedStat.DateClosed ## property specific to this report
                ClosedBy      = $ReopenedStat.ClosedBy ## property specific to this report
                DateReopened  = $ReopenedStat.DateReopened ## property specific to this report
                OpenedBy      = $ReopenedStat.OpenedBy ## property specific to this report
                Board         = $BaseStat.board.name
                Summary       = $BaseStat.summary
                Status        = $BaseStat.status.name
                Resource      = $BaseStat.resources
                Priority      = $BaseStat.priority.name
                TicketAge     = $TicketAge
                DateEntered   = $BaseStat._info.dateEntered.ToShortDateString()
            }

            $ObjCollection += $obj
        }

        if ($TotalItems -and $ItemIteration -le $TotalItems) {
            Write-Progress -Activity "Analyzing tickets..." -Status "$([math]::Round((($ItemIteration/$TotalItems)*100),2))%" -PercentComplete (($ItemIteration / $TotalItems) * 100)
        }
    }

    END {
        $ObjCollection | Export-Csv -Path $CSVPath -NoTypeInformation -Force
        $ObjCollection | ConvertTo-Html -CssUri reportstyle.css | Out-File -FilePath $HTMLPath -Force
    }
}

########################################
#endregion APP Functions