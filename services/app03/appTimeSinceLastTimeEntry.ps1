#######################
#region APP DESCRIPTION
#######################

$script:appName = "appTimeSinceLastTimeEntry"
$FrequencyMinutes = 2

##########################
#endregion APP DESCRIPTION
##########################

#region SHARED INTITALIZATION

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

#####################
#region APP FUNCTIONS
#####################

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

########################
#endregion APP FUNCTIONS
########################

New-CWMLog -Type "Info" -Message "STARTING $($script:appName.ToUpper()) SERVICE"

while ($true) {
    $Start = Get-Date
    New-CWMLog -Type "Info" -Message "Starting new iteration of $script:appName"

    ##########################
    #region APP SPECIFIC LOGIC
    ##########################

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
        New-CWMLog -Type "Info" -Message "Generating report..."
        $Id | New-CWMTimeSinceLastTimeEntryReport `
            -CSVPath "$dataPath/appTimeSinceLastTimeEntry.csv" `
            -HTMLPath "$dataPath/appTimeSinceLastTimeEntry.html" `
            -ItemsToDisplay 1000
        New-CWMLog -Type "Info" -Message "Completed report"
    }
    catch {
        New-CWMLog -Type "Error" -Message "Failed to generate time since last time entry report: $($_.Exception.Message)"
    }

    #############################
    #endregion APP SPECIFIC LOGIC
    #############################

    #region App Iteration Handler
    $FrequencyMilliseconds = $FrequencyMinutes * 60 * 1000
    $End = Get-Date
    $OperationTime = ($End - $Start).TotalMilliseconds
    $RemainderDelay = $FrequencyMilliseconds - $OperationTime
    if ($RemainderDelay -gt 0) {
        New-CWMLog -Type "Info" -Message "Iteration completed in $([math]::Round($OperationTime / 1000, 2)) seconds. Sleeping for $([math]::Round($RemainderDelay / 1000, 2)) seconds."
        Start-Sleep -Milliseconds $RemainderDelay
    }
    else {
        New-CWMLog -Type "Warning" -Message "Iteration took longer ($([math]::Round($OperationTime / 1000, 2)) seconds) than the configured frequency of $FrequencyMinutes minutes. Starting next iteration immediately."
    }
    #endregion App Iteration Handler
}
