#######################
#region APP DESCRIPTION
#######################

$script:appName = "appTicketsWorkedToday"
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

function New-CWMTicketsWorkedTodayReport {
    <#
    .SYNOPSIS
        Generates a CSV and HTML report for showing real-time statistics on tickets by tech in the current day.
    .DESCRIPTION
        Generates a CSV and HTML report for showing real-time statistics on tickets by tech in the current day.
    .EXAMPLE
        PS C:\> Get-CWMTicketsWorkedTodayStatistics | New-CWMTicketsWorkedTodayReport
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipelineByPropertyName)]
        [string[]]$TechId,

        [string[]]$BoardFilter = $boardsEnv,

        [ValidatePattern('([0-9]|[A-Z])\.csv$')]
        [Parameter(HelpMessage = "Enter a full file path and name ending in .csv")]
        [string]$CSVPath = (Get-Location).Path + "\CWMTicketsWorkedTodayReport.csv",

        [ValidatePattern('([0-9]|[A-Z])\.html$')]
        [Parameter(HelpMessage = "Enter a full file path and name ending in .html")]
        [string]$HTMLPath = (Get-Location).Path + "\CWMTicketsWorkedTodayReport.html",

        [int]$TotalItems,

        [int]$UTCTimeZone = -5
    )

    BEGIN {
        $ItemIteration = 0
        $ObjCollection = @()

        $TechByBoard = Get-CWMTechByBoard
    }

    PROCESS {
        $ItemIteration++

        $CurrentTech = $_.TechId
        $Board = $TechByBoard | Where-Object { $_.CWMName -eq $CurrentTech }
        
        if ($boardFilter -contains $Board.Team) {
            $obj = [PSCustomObject]@{
                Technician           = $_.TechFullName
                Board                = $Board.Team
                TicketsWorked        = $_.TicketsWorked ## property specific to this report
                TotalTimeEntries     = $_.TotalTimeEntries ## property specific to this report
                TotalHours           = [math]::Round($_.TotalHours, 1) ## property specific to this report
                AvgTimeEntryDuration = [math]::Round($_.AvgTimeEntryDuration, 1) ## property specific to this report
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

    # Generate appTicketsWorkedToday report
    try {
        New-CWMLog -Type "Info" -Message "Generating report $script:appName..."
        Get-CWMTicketsWorkedTodayStatistics | New-CWMTicketsWorkedTodayReport `
            -CSVPath "$dataPath/appTicketsWorkedToday.csv" `
            -HTMLPath "$dataPath/appTicketsWorkedToday.html"
        New-CWMLog -Type "Info" -Message "Completed report $script:appName"
    }
    catch {
        New-CWMLog -Type "Error" -Message "Failed to generate $script:appName report: $($_.Exception.Message)"
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
