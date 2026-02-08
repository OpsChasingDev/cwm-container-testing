#######################
#region APP DESCRIPTION
#######################

$script:appName = "appPOCOpenTicket"
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

function New-CWMPOCOpenTicketReport {
    <#
    .SYNOPSIS
        Generates a CSV and HTML report for opened tickets with a contact labeled "Owner","POC","VIP","Primary Contact", or "Decision Maker".
    .DESCRIPTION
        Generates a CSV and HTML report for opened tickets with a contact labeled "Owner","POC","VIP","Primary Contact", or "Decision Maker".
    .EXAMPLE
        PS C:\> (Get-CWMFullTicket -Board "Team 1","Team 2","Team 3","Escalations","Build Team","Staff Aug").id | New-CWMPOCOpenTicketReport
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
        $ContactLabelCol = @("Owner", "POC", "VIP", "Primary Contact", "Decision Maker")
    }

    PROCESS {
        $ItemIteration++

        $BaseStat = Get-CWMTicket -id $TicketID
        
        if ($BaseStat.contact) {
            $ContactLabelName = (Get-CWMContact -id $BaseStat.contact.id).types.name
    
            if ($ContactLabelName -and (Compare-Object $ContactLabelName $ContactLabelCol -IncludeEqual -ExcludeDifferent)) {
                $TicketAge = ($Today - ($BaseStat._info.dateEntered).AddHours($UTCTimeZone)).Days
                
                $obj = [PSCustomObject]@{
                    TicketID    = $BaseStat.id
                    Company     = $BaseStat.company.name
                    Contact     = $BaseStat.contact.name
                    Board       = $BaseStat.board.name
                    Summary     = $BaseStat.summary
                    Status      = $BaseStat.status.name
                    Resource    = $BaseStat.resources
                    Priority    = $BaseStat.priority.name
                    TicketAge   = $TicketAge
                    DateEntered = $BaseStat._info.dateEntered.ToShortDateString()
                }
                $ObjCollection += $obj
            }
            else {
                Write-Verbose -Message "Ticket $TicketID does not have a contact labeled with any of these options: $ContactLabelCol."
            }
        }
        else {
            Write-Verbose -Message "Ticket $TicketID does not have a contact."
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

    # Generate reopened ticket report
    try {
        New-CWMLog -Type "Info" -Message "Generating report..."
        $Id | New-POCOpenTicketReport `
            -CSVPath "$dataPath/appPOCOpenTicket.csv" `
            -HTMLPath "$dataPath/appPOCOpenTicket.html"
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
