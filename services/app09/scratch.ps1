break

#region Querying Tickets by Date Entered

# get the date a ticket was entered
$t = Get-CWMFullTicket
$t[0]._info.dateEntered

# use dateEntered as a condition to the REST API
$t = Get-CWMFullTicket -condition "dateEntered > [$(Get-Date)]" -ClosedStatus All

# get tickets entered in the last 7 days
$t = Get-CWMFullTicket -condition "dateEntered > [$((Get-Date).ToUniversalTime().AddDays(-7))]" -ClosedStatus All

# get tickets entered in the last 7 days on the Team 1 or Team 2 boards
$t = Get-CWMFullTicket -condition "dateEntered > [$((Get-Date).ToUniversalTime().AddDays(-7))] AND (board/name = 'Team 1' OR board/name = 'Team 2')" -ClosedStatus All

# new way to query tickets entered in the last 7 days on the Team 1 or Team 2 boards
$t2 = Get-CWMFullTicket -Board 'Team 1', 'Team 2' -ClosedStatus All -LastDays 7 -Verbose

#endregion

#region Turning Ticket Summaries Into Keywords

$t2 = Get-CWMFullTicket -Board 'Team 1', 'Team 2' -ClosedStatus All -LastDays 7 -Verbose

# single ticket - split summary by " ", trim, and exclude result "-"
($t2[0].summary -split " ").trim() | Where-Object {$_ -ne "-"}

# collection of tickets - split summaries by " ", trim, and exclude result "-"
$t2 | ForEach-Object { ($_.summary).Split(" ").Trim() | Where-Object { $_ -ne "-" } }

# store and group results of top 20 without common strings
$exceptions = "-",":","&","issue","add","a", "the", "and", "or", "but", "is", "are", "was", "were", "in", "on", "at", "to", "for", "with", "cannot", "be", "by", "of", "from", "as", "that", "this", "it", "its", "if", "then", "else", "when", "while", "do", "does", "did", "not", "no", "yes", "can", "will", "just", "up", "down", "out", "over", "under", "again", "further", "here", "there", "all", "any", "both", "each", "few", "more", "most", "other", "some", "such", "only", "own", "same", "so", "than", "too", "very", "should", "now"
$keywords = $t2 | ForEach-Object { ($_.summary).Split(" ").Trim() | Where-Object { $_ -notin $exceptions -and $_ } }
$keywords | Group-Object | Sort-Object -Property Count -Descending -Top 20

#endregion

#region Find Associated Tickets

# for each keyword, find tickets that include that keyword in the summary
$Collection = @()
foreach ($k in $keywords) {
    $t = $t2 | Where-Object { $_.summary -like "*$k*" }
    if ($t) {
        $obj = [PSCustomObject]@{
            Keyword = $k
            Tickets = $t.id
        }
        $Collection += $obj
    }
}
Write-Output $Collection

# store only the top 20 keywords, find their associated tickets, and build the data table to include the keyword, the count of associated tickets, and the list of associated ticket IDs
$TopKeywords = $keywords | Group-Object | Sort-Object -Property Count -Descending -Top 20 | Select-Object -ExpandProperty Name
$Collection = @()
foreach ($k in $TopKeywords) {
    $t = $t2 | Where-Object { $_.summary -like "*$k*" }
    if ($t) {
        $obj = [PSCustomObject]@{
            Keyword = $k
            Count = $t.Count
            Tickets = $t.id
        }
        $Collection += $obj
    }
}
Write-Output $Collection

# turn the "Tickets" property into a string of the numbers separated by spaces so they can all show up in a CSV export
$Collection | ForEach-Object { $_.Tickets = ($_.Tickets -join " ") }
$Collection | Export-Csv -Path "KeywordTickets.csv" -NoTypeInformation

#endregion