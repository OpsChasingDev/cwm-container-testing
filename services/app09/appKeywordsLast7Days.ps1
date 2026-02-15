#######################
#region APP DESCRIPTION
#######################

$script:appName = "appKeywordsLast7Days"
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

# none exist for this app; all logic occurs in the APP SPECIFIC LOGIC region

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

    # Retrieve all tickets from specified boards
    try {
        $Tickets = Get-CWMFullTicket -Board $boardsEnv -ClosedStatus All -LastDays 7 # uses dateEntered as a condition to the REST API to only retrieve tickets created in the last 7 days, which improves performance by reducing the number of tickets returned and processed
        New-CWMLog -Type "Info" -Message "Retrieved $($Tickets.Count) tickets from specified boards created on or after $((Get-Date).AddDays(-7).ToUniversalTime().AddHours(-5)) EST"
    }
    catch {
        New-CWMLog -Type "Error" -Message "Failed to retrieve tickets: $($_.Exception.Message)"
    }

    try {
        New-CWMLog -Type "Info" -Message "Generating report..."
        # Create and group keywords from ticket summaries, excluding common words
        $exceptions = "|","new","request","YOUR","TICKET","RE:","-",":","&","issue","add","a", "the", "and", "or", "but", "is", "are", "was", "were", "in", "on", "at", "to", "for", "with", "cannot", "be", "by", "of", "from", "as", "that", "this", "it", "its", "if", "then", "else", "when", "while", "do", "does", "did", "not", "no", "yes", "can", "will", "just", "up", "down", "out", "over", "under", "again", "further", "here", "there", "all", "any", "both", "each", "few", "more", "most", "other", "some", "such", "only", "own", "same", "so", "than", "too", "very", "should", "now"
        $keywords = $Tickets | ForEach-Object { ($_.summary).Split(" ").Trim() | Where-Object { $_ -notin $exceptions -and $_ } } # separates summary strings by spaces, trims whitespace, and excludes common words and empty results
        $TopKeywords = $keywords | Group-Object | Sort-Object -Property Count -Descending -Top 20 | Select-Object -ExpandProperty Name

        # Builds objects for each of the top 20 keywords that include the keyword, the count of associated tickets, and the list of associated ticket IDs.  Objects are stored in a collection.
        $Collection = @()
        foreach ($k in $TopKeywords) {
            $t = $Tickets | Where-Object { $_.summary -like "*$k*" }
            if ($t) {
                $obj = [PSCustomObject]@{
                    Keyword = $k
                    Count = $t.Count
                    TicketID = $t.id
                }
                $Collection += $obj
            }
        }

        # turn the "Tickets" property into a string of the numbers separated by spaces so they can all show up in a CSV export, then export results to CSV and HTML files
        $Collection | ForEach-Object { $_.TicketID = ($_.TicketID -join " ") }
        
        # Generate keywords last 7 days report
        $Collection | Export-Csv -Path "$dataPath/appKeywordsLast7Days.csv" -NoTypeInformation -Force
        $Collection | ConvertTo-Html -CssUri reportstyle.css | Out-File -FilePath "$dataPath/appKeywordsLast7Days.html" -Force
        New-CWMLog -Type "Info" -Message "Completed report"
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
