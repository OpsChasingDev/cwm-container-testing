var boardSelect;
var selectedReportCSV = '';
var sidebarLinks;
var descriptions = {};
var interval;

function loadPage(event, url) {
    event.preventDefault(); // Prevent the link from navigating to the URL
    // clear interval defined in var "interval" to prevent multiple loops running
    clearInterval(interval);

    var xhr = new XMLHttpRequest();

    xhr.onreadystatechange = function () {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                document.getElementById("viewport").innerHTML = xhr.responseText;
                var csvName = url.split('/').pop().replace('.html', '.csv');
                selectedReportCSV = csvName;

                // Call loadTable function to update TicketID hyperlinks
                ticketHyperlink();

                // Filter table rows based on selected board
                filterTableRows();

                // Add click listeners to table headers for sorting
                addColumnHeaderListeners();

                // Add click listeners to sidebar links
                addSidebarLinkListeners();

                // Loads the description for the report
                loadDescriptions();

                // Update the selected link in the sidebar
                updateSelectedLink(url);

                // Update the description based on the selected link
                updateDescription(url);
            } else {
                console.error(xhr.statusText);
            }
        }
    };

    boardSelect = document.getElementById('board-select');
    boardSelect.addEventListener('change', filterTableRows);

    xhr.open("GET", 'report/' + url, true);
    xhr.send();

    // add a 5 minute interval loop to refresh the selected report
    interval = setInterval(function () {
        xhr.open("GET", 'report/' + url, true);
        xhr.send();
        // write to console to confirm the loop is running
        console.log("Refreshing report...");
    }, 300000);
}

function updateSelectedLink(url) {
    // Remove clicked class from all links
    sidebarLinks.forEach(function (link) {
        link.classList.remove('clicked');
    });

    // Find the corresponding link based on the URL
    var selectedLink = Array.from(sidebarLinks).find(function (link) {
        return link.getAttribute('href') === url;
    });

    // Add clicked class to the selected link
    if (selectedLink) {
        selectedLink.classList.add('clicked');
    }
}

function download() {
    // only operate if selectedReportCSV is not empty
    if (selectedReportCSV !== '') {
        var element = document.createElement('a');
        // the below line is for ease of changing the path to the CSV file if needed in the future
        var reportFullPath = 'report/' + selectedReportCSV;
        element.setAttribute('href', reportFullPath);
        element.setAttribute('download', selectedReportCSV);
        element.style.display = 'none';
        document.body.appendChild(element);
        element.click();
        document.body.removeChild(element);
    } else {
        console.error("No report selected");
    }
}

function filterTableRows() {
    var selectedBoards = Array.from(boardSelect.selectedOptions).map(option => option.value);
    var dataTable = document.querySelector('table');
    var headerRow = dataTable.getElementsByTagName('tr')[0];
    var columnIndex = -1;

    // Find the column index for the "Board" header
    var headers = headerRow.getElementsByTagName('th');
    for (var i = 0; i < headers.length; i++) {
        if (headers[i].textContent.trim() === 'Board') {
            columnIndex = i;
            break;
        }
    }

    if (columnIndex === -1) {
        console.error("Column 'Board' not found in the table.");
        return;
    }

    var rows = dataTable.getElementsByTagName('tr');

    for (var i = 1; i < rows.length; i++) {
        var row = rows[i];
        var cells = row.getElementsByTagName('td');

        if (columnIndex < cells.length) {
            var boardColumn = cells[columnIndex];
            var boardValue = boardColumn.textContent.trim();

            if (selectedBoards.includes(boardValue) || selectedBoards.includes('all')) {
                row.style.display = ''; // Show row
            } else {
                row.style.display = 'none'; // Hide row
            }
        }
    }
}

function ticketHyperlink() {
    // Get the table
    var table = document.querySelector("table");

    // Get the table rows
    var rows = table.getElementsByTagName("tr");

    // Find the column index for "TicketID" header
    var headerRow = rows[0];
    var cells = headerRow.getElementsByTagName("th");
    var columnIndex = -1;

    for (var i = 0; i < cells.length; i++) {
        if (cells[i].textContent.trim() === "TicketID") {
            columnIndex = i;
            break;
        }
    }

    if (columnIndex === -1) {
        console.error("Column 'TicketID' not found in the table.");
        return;
    }

    // Iterate over the rows (skip the header row)
    for (var i = 1; i < rows.length; i++) {
        var ticketIdCell = rows[i].cells[columnIndex];

        // Get the TicketID value
        var ticketId = ticketIdCell.textContent.trim();

        // Create the hyperlink element
        var link = document.createElement("a");
        link.href = "https://connect.savantcts.com/v4_6_release/ConnectWise.aspx?locale=en_US&routeTo=ServiceFV&recid=" + ticketId;
        link.textContent = ticketId;
        link.target = "_blank"; // Open link in a new tab

        // Replace the content of the TicketID cell with the hyperlink
        ticketIdCell.innerHTML = "";
        ticketIdCell.appendChild(link);
    }
}

function addColumnHeaderListeners() {
    var sortOrders = {};
    var dataTable = document.querySelector('table');
    var headerRow = dataTable.getElementsByTagName('tr')[0];
    var headers = headerRow.getElementsByTagName('th');

    // Add click event listener to each column header
    for (var i = 0; i < headers.length; i++) {
        headers[i].addEventListener('click', handleColumnClick);
        headers[i].style.cursor = 'pointer';
    }

    function handleColumnClick(event) {
        var clickedColumn = event.target;
        var columnText = clickedColumn.textContent.trim();
        var columnIndex = Array.from(headers).indexOf(clickedColumn);

        // Toggle the sort order for the clicked column
        sortOrders[columnIndex] = sortOrders[columnIndex] === 'asc' ? 'desc' : 'asc';

        // Sort the row data based on the clicked column and sort order
        sortTableByColumn(columnIndex, sortOrders[columnIndex]);

        // Update the table with the sorted data
        updateTable();
    }


    function sortTableByColumn(columnIndex, sortOrder) {
        var dataTable = document.querySelector('table');
        var rows = Array.from(dataTable.getElementsByTagName('tr')).slice(1);

        rows.sort(function (a, b) {
            var aValue = a.cells[columnIndex].textContent.trim();
            var bValue = b.cells[columnIndex].textContent.trim();

            // Compare values based on sort order
            var compareResult = aValue.localeCompare(bValue, undefined, { numeric: true, sensitivity: 'base' });
            return sortOrder === 'desc' ? compareResult * -1 : compareResult;
        });

        dataTable.tBodies[0].append(...rows);
    }


    function updateTable() {
        // Call loadTable function to update TicketID hyperlinks
        ticketHyperlink();

        // Filter table rows based on selected board
        filterTableRows();
    }
}

function addSidebarLinkListeners() {
    // Get all sidebar links
    sidebarLinks = document.querySelectorAll('#sidebar a');

    // Add event listener to each sidebar link
    sidebarLinks.forEach(function (link) {
        link.addEventListener('click', handleSidebarLinkClick);
    });

    function handleSidebarLinkClick(event) {
        // Remove clicked class from all links
        sidebarLinks.forEach(function (link) {
            link.classList.remove('clicked');
        });

        // Add clicked class to the clicked link
        event.target.classList.add('clicked');

        // Update the description based on the clicked link
        updateDescription(event.target.href); // Pass the full URL as linkHref
    }
}

function loadDescriptions() {
    var xhr = new XMLHttpRequest();

    xhr.onreadystatechange = function () {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                descriptions = JSON.parse(xhr.responseText);
                updateDescription();
            } else {
                console.error(xhr.statusText);
            }
        }
    };

    xhr.open("GET", "data/desc.json", true);
    xhr.send();
}

function updateDescription(linkHref) {
    var descriptionSection = document.getElementById('description-data');

    // Use the currently selected link if linkHref is not provided
    if (!linkHref) {
        var selectedLink = document.querySelector('#sidebar a.clicked');
        linkHref = selectedLink.getAttribute('href');
    }

    var description = descriptions[linkHref];

    // Update the description section in the sidebar
    descriptionSection.textContent = description;
}