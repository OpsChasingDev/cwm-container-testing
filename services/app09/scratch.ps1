break

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
$t = Get-CWMFullTicket -BoardName 'Team 1','Team 2' -ClosedStatus All -LastDays 7