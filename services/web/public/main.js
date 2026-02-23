var boardSelect;
var selectedReportCSV = '';
var sidebarLinks;
var descriptions = {};
var interval;
var cwmServer = null; // Will be loaded from server config
var environment = 'production'; // Will be loaded from server config
var currentContainerName = null; // Track which container's report is currently displayed
var containerStatusPoller = null; // Track the status polling interval
var containerStates = {}; // Track state of containers {containerName: {state: 'running'|'stopped'|'unknown', actualState: 'running'|'stopped'|'waiting'|'unknown'}}
var containerLastActionTime = {}; // Track when actions were last performed (for rate limiting)

// Create a tabbed viewport structure
function createTabbedViewport(reportContent, containerName) {
    currentContainerName = containerName;
    const tabsHTML = `
        <div class="tabs-container" data-container="${containerName}">
            <div class="tab-buttons">
                <button class="tab-button active" onclick="switchTab(event, 'data-tab')">Data</button>
                <button class="tab-button" onclick="switchTab(event, 'logs-tab')">Logs</button>
            </div>
            <div id="data-tab" class="tab-content active">
                ${reportContent}
            </div>
            <div id="logs-tab" class="tab-content">
                <div class="logs-content" style="white-space: pre-wrap; font-family: monospace; font-size: 12px; line-height: 1.5;">Loading logs...</div>
            </div>
        </div>
    `;
    return tabsHTML;
}

// Handle tab switching
function switchTab(event, tabId) {
    event.preventDefault();
    
    // Hide all tab contents
    const tabContents = document.querySelectorAll('.tab-content');
    tabContents.forEach(content => content.classList.remove('active'));
    
    // Remove active class from all tab buttons
    const tabButtons = document.querySelectorAll('.tab-button');
    tabButtons.forEach(button => button.classList.remove('active'));
    
    // Show the selected tab content and activate the button
    const selectedTabContent = document.getElementById(tabId);
    if (selectedTabContent) {
        selectedTabContent.classList.add('active');
    }
    
    // Add active class to the clicked button
    event.target.classList.add('active');
    
    // Update download button based on active tab
    updateDownloadButton(tabId);
    
    // If switching to logs tab, fetch and display logs
    if (tabId === 'logs-tab' && currentContainerName) {
        fetchAndDisplayLogs(currentContainerName);
    }
}

// Update download button based on active tab
function updateDownloadButton(tabId) {
    const downloadButton = document.getElementById('downloadButton');
    if (!downloadButton) return;
    
    if (tabId === 'logs-tab') {
        downloadButton.textContent = 'Download Logs';
        downloadButton.onclick = function() { downloadLogs(); };
    } else {
        downloadButton.textContent = 'Download CSV';
        downloadButton.onclick = function() { download(); };
    }
}

// Fetch and display logs for the current container
function fetchAndDisplayLogs(containerName) {
    const logsContentDiv = document.querySelector('.logs-content');
    if (!logsContentDiv) return;
    
    logsContentDiv.textContent = 'Loading logs...';
    
    fetch(`/logs/${containerName}`)
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            return response.text();
        })
        .then(data => {
            // Reverse the logs so newest entries appear at the top
            const lines = data.split('\n');
            const reversedLines = lines.reverse();
            const reversedContent = reversedLines.join('\n');
            logsContentDiv.textContent = reversedContent;
        })
        .catch(error => {
            console.error('Error fetching logs:', error);
            logsContentDiv.textContent = `Error loading logs: ${error.message}`;
        });
}

// Handle power control button clicks - show confirmation modal
function handlePowerControl(event, containerName) {
    event.stopPropagation(); // Prevent triggering loadPage
    
    const statusObj = containerStates[containerName] || { state: 'unknown', actualState: 'unknown' };
    const currentState = statusObj.state || 'unknown';
    const actionType = currentState === 'running' ? 'stop' : 'start';
    const actionText = actionType === 'stop' ? 'Stop' : 'Start';
    
    showContainerConfirmation(containerName, actionType, actionText);
}

// Show confirmation modal
function showContainerConfirmation(containerName, action, actionText) {
    const modal = document.getElementById('powerControlModal');
    if (!modal) return;
    
    const modalTitle = document.getElementById('powerControlModalTitle');
    const modalMessage = document.getElementById('powerControlModalMessage');
    const confirmButton = document.getElementById('powerControlConfirmBtn');
    
    modalTitle.textContent = `${actionText} Container`;
    modalMessage.textContent = `Are you sure you want to ${action} the container for ${containerName}?`;
    
    confirmButton.onclick = function() {
        modal.style.display = 'none';
        executeContainerAction(containerName, action);
    };
    
    modal.style.display = 'block';
}

// Close modal
function closeContainerConfirmation() {
    const modal = document.getElementById('powerControlModal');
    if (modal) {
        modal.style.display = 'none';
    }
}

// Execute container start/stop action
function executeContainerAction(containerName, action) {
    const button = document.querySelector(`button[onclick*="handlePowerControl"][onclick*="${containerName}"]`);
    if (!button) return;
    
    // Rate limiting: prevent rapid consecutive actions
    const lastAction = containerLastActionTime[containerName] || 0;
    if (Date.now() - lastAction < 5000) {
        alert('Please wait before performing another action on this container');
        return;
    }
    
    // Set button to transitioning state
    setButtonTransitioning(button, true);
    containerStates[containerName] = { state: 'transitioning', actualState: 'waiting' };
    updatePowerButtonIcon(button, 'transitioning');
    
    fetch(`/container-action/${containerName}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ action: action })
    })
    .then(response => {
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        return response.json();
    })
    .then(data => {
        console.log(`Container action ${action} initiated for ${containerName}`);
        containerLastActionTime[containerName] = Date.now();
        
        // Poll for state change with timeout
        pollContainerState(containerName, action, button, 60000); // 60 second timeout
    })
    .catch(error => {
        console.error('Error executing container action:', error);
        setButtonTransitioning(button, false);
        containerStates[containerName] = { state: 'unknown', actualState: 'unknown' };
        updatePowerButtonIcon(button, 'unknown');
        alert(`Failed to ${action} container: ${error.message}`);
    });
}

// Poll container state until it changes
function pollContainerState(containerName, expectedAction, button, timeout) {
    const startTime = Date.now();
    const pollInterval = 2000; // Poll every 2 seconds
    const expectedState = expectedAction === 'start' ? 'running' : 'stopped';
    
    const poller = setInterval(() => {
        const elapsed = Date.now() - startTime;
        
        // Check timeout
        if (elapsed > timeout) {
            clearInterval(poller);
            setButtonTransitioning(button, false);
            console.error(`Container state change timeout for ${containerName}`);
            alert(`Timeout waiting for container to ${expectedAction}`);
            fetchContainerStatus(containerName); // Try one more time
            return;
        }
        
        // Query current state
        fetch(`/container-status/${containerName}`)
            .then(response => response.json())
            .then(data => {
                console.log(`Polling ${containerName} state: ${data.state}, actualState: ${data.actualState}`);
                
                // Check if in transition (waiting state or unknown)
                const isTransitioning = data.actualState === 'waiting' || data.actualState === 'unknown';
                
                if (data.state === expectedState && !isTransitioning) {
                    // State change confirmed
                    clearInterval(poller);
                    setButtonTransitioning(button, false);
                    containerStates[containerName] = {
                        state: data.state,
                        actualState: data.actualState || data.state
                    };
                    updatePowerButtonIcon(button, data.state);
                    console.log(`Container ${containerName} successfully ${expectedAction}ed`);
                } else if (isTransitioning) {
                    // Still in transition, keep polling
                    updatePowerButtonIcon(button, 'transitioning');
                }
            })
            .catch(error => {
                console.error('Error polling container state:', error);
            });
    }, pollInterval);
}

// Fetch and update container status for a specific container
function fetchContainerStatus(containerName) {
    fetch(`/container-status/${containerName}`)
        .then(response => response.json())
        .then(data => {
            // Store full status object with both state and actualState
            containerStates[containerName] = {
                state: data.state,
                actualState: data.actualState || data.state
            };
            updatePowerButtonsForContainer(containerName);
        })
        .catch(error => {
            console.error(`Error fetching status for ${containerName}:`, error);
            containerStates[containerName] = {
                state: 'unknown',
                actualState: 'unknown'
            };
        });
}

// Update all power buttons for a specific container
function updatePowerButtonsForContainer(containerName) {
    const buttons = document.querySelectorAll(`button[onclick*="handlePowerControl"][onclick*="${containerName}"]`);
    buttons.forEach(button => {
        const statusObj = containerStates[containerName] || { state: 'unknown', actualState: 'unknown' };
        
        // Determine display state based on actualState
        let displayState = statusObj.state;
        if (statusObj.actualState === 'waiting') {
            displayState = 'transitioning';
        }
        
        updatePowerButtonIcon(button, displayState);
    });
}

// Update power button icon based on state
function updatePowerButtonIcon(button, state) {
    let icon, title, disabled = false;
    
    switch (state) {
        case 'running':
            icon = '🟢'; // Green circle - running
            title = 'Container is running (click to stop)';
            break;
        case 'stopped':
            icon = '🔴'; // Red circle - stopped
            title = 'Container is stopped (click to start)';
            break;
        case 'transitioning':
            icon = '⏳'; // Hourglass - transitioning
            title = 'Container state is changing...';
            disabled = true;
            break;
        case 'unknown':
        default:
            icon = '❓'; // Question mark - unknown
            title = 'Container state unknown';
            break;
    }
    
    button.textContent = icon;
    button.title = title;
    button.disabled = disabled;
}

// Set button to transitioning state
function setButtonTransitioning(button, isTransitioning) {
    button.disabled = isTransitioning;
    if (isTransitioning) {
        button.dataset.previousContent = button.textContent;
        button.textContent = '⏳';
    } else {
        button.textContent = button.dataset.previousContent || '❓';
    }
}

// Initialize container status polling when report loads
function startContainerStatusPolling(containerName) {
    if (containerStatusPoller) {
        clearInterval(containerStatusPoller);
    }
    
    // Fetch initial status
    fetchContainerStatus(containerName);
    
    // Poll every 30 seconds
    containerStatusPoller = setInterval(() => {
        fetchContainerStatus(containerName);
    }, 30000);
}

// Stop container status polling
function stopContainerStatusPolling() {
    if (containerStatusPoller) {
        clearInterval(containerStatusPoller);
        containerStatusPoller = null;
    }
}


// Load and update header based on environment on page load
fetch('/config/environment')
  .then(response => response.json())
  .then(data => {
    environment = data.environment;
    if (environment === 'staging') {
      const pageTitle = document.getElementById('page-title');
      if (pageTitle) {
        pageTitle.textContent = 'CWM Custom Reporting - STAGING';
      }
    }
  })
  .catch(error => console.log('Environment config not available'));

// Load and populate board options from configuration
fetch('/config/ticketing-boards')
  .then(response => response.json())
  .then(data => {
    if (data.boards && data.boards.length > 0) {
      const boardSelect = document.getElementById('board-select');
      if (boardSelect) {
        // Clear existing options except the "All Boards" option
        const allBoardsOption = boardSelect.querySelector('option[value="all"]');
        boardSelect.innerHTML = '';
        if (allBoardsOption) {
          boardSelect.appendChild(allBoardsOption);
        }
        
        // Add board options from configuration
        data.boards.forEach(board => {
          const option = document.createElement('option');
          option.value = board;
          option.textContent = board;
          boardSelect.appendChild(option);
        });
      }
    }
  });

function loadPage(event, url) {
    event.preventDefault(); // Prevent the link from navigating to the URL
    // clear interval defined in var "interval" to prevent multiple loops running
    clearInterval(interval);

    // Load CWM server URL from config endpoint before making requests
    var configXhr = new XMLHttpRequest();
    configXhr.onreadystatechange = function () {
        if (configXhr.readyState === XMLHttpRequest.DONE) {
            if (configXhr.status === 200) {
                var config = JSON.parse(configXhr.responseText);
                cwmServer = config.cwmServer;
                loadReport(url);
            } else {
                console.error('Failed to load CWM server configuration');
            }
        }
    };
    configXhr.open("GET", 'config/cwm-server', true);
    configXhr.send();
}

function loadReport(url) {
    var xhr = new XMLHttpRequest();

    // Extract base name from URL (e.g., TimeSinceLastTimeEntryReport.html -> TimeSinceLastTimeEntry)
    var baseName = url.split('/').pop().replace('Report.html', '');
    var appName = 'app' + baseName;
    var reportFilename = appName + '.html';
    var reportPath = '/report/' + reportFilename;

    xhr.onreadystatechange = function () {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                // Wrap the report content in a tabbed interface
                const tabbedContent = createTabbedViewport(xhr.responseText, appName);
                document.getElementById("viewport").innerHTML = tabbedContent;
                
                var csvName = appName + '.csv';
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

                // Get the Last-Modified header from the response
                var lastModified = xhr.getResponseHeader('Last-Modified');
                
                // Update the timestamp with the file's Last-Modified date
                updateTimestamp(lastModified);
                
                // Start polling container status
                startContainerStatusPolling(appName);
            } else {
                console.error(xhr.statusText);
            }
        }
    };

    boardSelect = document.getElementById('board-select');
    boardSelect.addEventListener('change', filterTableRows);

    xhr.open("GET", reportPath, true);
    xhr.send();

    // add a 5 minute interval loop to refresh the selected report
    interval = setInterval(function () {
        xhr.open("GET", reportPath, true);
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
        // Use the API endpoint to serve the CSV file
        var reportFullPath = '/report/' + selectedReportCSV;
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

function downloadLogs() {
    // Download logs for the current container
    if (currentContainerName) {
        var element = document.createElement('a');
        // Use the API endpoint to serve the log file
        var logsPath = '/download-logs/' + currentContainerName;
        element.setAttribute('href', logsPath);
        element.style.display = 'none';
        document.body.appendChild(element);
        element.click();
        document.body.removeChild(element);
    } else {
        console.error("No container selected");
    }
}

function updateTimestamp(lastModifiedHeader) {
    var date;
    
    if (lastModifiedHeader) {
        // Parse the HTTP Last-Modified header (format: "Wed, 21 Oct 2015 07:28:00 GMT")
        date = new Date(lastModifiedHeader);
    } else {
        date = new Date();
    }
    
    var year = date.getFullYear();
    var month = String(date.getMonth() + 1).padStart(2, '0');
    var day = String(date.getDate()).padStart(2, '0');
    var hours = String(date.getHours()).padStart(2, '0');
    var minutes = String(date.getMinutes()).padStart(2, '0');
    var seconds = String(date.getSeconds()).padStart(2, '0');
    
    var formattedDateTime = year + '-' + month + '-' + day + ' ' + hours + ':' + minutes + ':' + seconds;
    var timestampElement = document.getElementById('dataTimestamp');
    timestampElement.textContent = 'Date: ' + formattedDateTime;
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
        link.href = "https://" + cwmServer + "/v4_6_release/ConnectWise.aspx?locale=en_US&routeTo=ServiceFV&recid=" + ticketId;
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
