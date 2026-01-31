/**
 * CWM Custom Reporting Server - Main Application Logic
 * Handles report loading, filtering, sorting, and CSV downloads
 */

class ReportingApp {
    constructor() {
        this.reports = new Map(); // Store report data by app name
        this.currentReport = null;
        this.currentData = null;
        this.filteredData = null;
        this.boardFilter = new Set();
        this.sortColumn = null;
        this.sortOrder = 'asc'; // 'asc' or 'desc'
        
        this.init();
    }

    async init() {
        this.cacheDOM();
        this.bindEvents();
        await this.loadAvailableReports();
    }

    cacheDOM() {
        this.appButtonsContainer = document.getElementById('appButtons');
        this.boardFilterSelect = document.getElementById('boardFilter');
        this.downloadBtn = document.getElementById('downloadBtn');
        this.reportContainer = document.getElementById('reportContainer');
    }

    bindEvents() {
        this.boardFilterSelect.addEventListener('change', (e) => this.handleBoardFilter());
        this.downloadBtn.addEventListener('click', () => this.downloadCSV());
    }

    /**
     * Scans the data directory and discovers available reports
     */
    async loadAvailableReports() {
        try {
            const response = await fetch('/api/reports');
            const reports = await response.json();
            
            this.renderAppButtons(reports);
        } catch (error) {
            console.error('Failed to load reports:', error);
            this.showError('Failed to load available reports');
        }
    }

    /**
     * Creates and renders app selection buttons
     */
    renderAppButtons(reports) {
        this.appButtonsContainer.innerHTML = '';
        
        reports.forEach(report => {
            const btn = document.createElement('button');
            btn.className = 'app-btn';
            btn.textContent = report.displayName;
            btn.dataset.appName = report.appName;
            
            btn.addEventListener('click', () => this.selectReport(report.appName, btn));
            btn.addEventListener('mouseover', function() {
                this.style.transform = 'translateX(4px)';
            });
            btn.addEventListener('mouseout', function() {
                this.style.transform = 'translateX(0)';
            });
            
            this.appButtonsContainer.appendChild(btn);
        });
    }

    /**
     * Loads and displays a report
     */
    async selectReport(appName, buttonElement) {
        try {
            this.currentReport = appName;
            
            // Update active button state
            document.querySelectorAll('.app-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            buttonElement.classList.add('active');
            
            // Load report data
            const response = await fetch(`/api/reports/${appName}`);
            const htmlContent = await response.text();
            
            this.displayReport(htmlContent);
            this.extractAndPopulateBoardFilter();
            this.downloadBtn.disabled = false;
            
        } catch (error) {
            console.error('Failed to load report:', error);
            this.showError(`Failed to load ${appName} report`);
            this.downloadBtn.disabled = true;
        }
    }

    /**
     * Displays the report in the main content area
     */
    displayReport(htmlContent) {
        this.reportContainer.innerHTML = htmlContent;
        
        // Convert to interactive table if it's an HTML table
        const tables = this.reportContainer.querySelectorAll('table');
        tables.forEach(table => {
            table.className = 'report-table';
            this.makeTableInteractive(table);
        });
        
        this.reportContainer.classList.add('loading');
        setTimeout(() => this.reportContainer.classList.remove('loading'), 300);
    }

    /**
     * Makes table headers sortable and interactive
     */
    makeTableInteractive(table) {
        const headers = table.querySelectorAll('thead th');
        headers.forEach((header, index) => {
            header.classList.add('sortable');
            header.addEventListener('click', () => this.sortTable(table, index, header));
            header.style.cursor = 'pointer';
        });
        
        // Extract board data for filtering
        this.extractTableData(table);
    }

    /**
     * Extracts table data for client-side operations
     */
    extractTableData(table) {
        const rows = table.querySelectorAll('tbody tr');
        this.currentData = [];
        
        rows.forEach(row => {
            const cells = row.querySelectorAll('td');
            const rowData = Array.from(cells).map(cell => cell.textContent.trim());
            this.currentData.push({
                element: row,
                data: rowData
            });
        });
        
        this.filteredData = [...this.currentData];
    }

    /**
     * Extracts unique board values from the table for the filter dropdown
     */
    extractAndPopulateBoardFilter() {
        const boards = new Set();
        const table = this.reportContainer.querySelector('table');
        
        if (!table) return;
        
        // Look for a "Board" column
        const headers = table.querySelectorAll('thead th');
        let boardColumnIndex = -1;
        
        headers.forEach((header, index) => {
            if (header.textContent.toLowerCase().includes('board')) {
                boardColumnIndex = index;
            }
        });
        
        if (boardColumnIndex === -1) {
            this.boardFilterSelect.innerHTML = '<option value="">No boards found</option>';
            this.boardFilterSelect.disabled = true;
            return;
        }
        
        // Extract board values
        const rows = table.querySelectorAll('tbody tr');
        rows.forEach(row => {
            const cells = row.querySelectorAll('td');
            if (cells[boardColumnIndex]) {
                boards.add(cells[boardColumnIndex].textContent.trim());
            }
        });
        
        // Populate select dropdown
        this.boardFilterSelect.innerHTML = '';
        this.boardFilterSelect.disabled = false;
        
        // Add default option
        const defaultOption = document.createElement('option');
        defaultOption.value = '';
        defaultOption.textContent = 'All Boards';
        this.boardFilterSelect.appendChild(defaultOption);
        
        // Add board options
        Array.from(boards).sort().forEach(board => {
            const option = document.createElement('option');
            option.value = board;
            option.textContent = board;
            this.boardFilterSelect.appendChild(option);
        });
        
        this.boardFilterSelect.addEventListener('change', () => this.handleBoardFilter());
    }

    /**
     * Handles board filter changes
     */
    handleBoardFilter() {
        this.boardFilter.clear();
        const selectedOptions = this.boardFilterSelect.selectedOptions;
        
        Array.from(selectedOptions).forEach(option => {
            if (option.value) {
                this.boardFilter.add(option.value);
            }
        });
        
        this.applyFilters();
    }

    /**
     * Applies board filter to table rows
     */
    applyFilters() {
        const table = this.reportContainer.querySelector('table');
        if (!table) return;
        
        const headers = table.querySelectorAll('thead th');
        let boardColumnIndex = -1;
        
        headers.forEach((header, index) => {
            if (header.textContent.toLowerCase().includes('board')) {
                boardColumnIndex = index;
            }
        });
        
        const rows = table.querySelectorAll('tbody tr');
        
        rows.forEach(row => {
            const cells = row.querySelectorAll('td');
            if (boardColumnIndex === -1 || this.boardFilter.size === 0) {
                row.classList.remove('hidden');
            } else {
                const boardValue = cells[boardColumnIndex].textContent.trim();
                if (this.boardFilter.has(boardValue)) {
                    row.classList.remove('hidden');
                } else {
                    row.classList.add('hidden');
                }
            }
        });
    }

    /**
     * Sorts table by column
     */
    sortTable(table, columnIndex, header) {
        const rows = table.querySelectorAll('tbody tr');
        const headers = table.querySelectorAll('thead th');
        
        // Remove sort indicators from all headers
        headers.forEach(h => {
            h.classList.remove('sorted-asc', 'sorted-desc');
        });
        
        // Determine sort order
        if (this.sortColumn === columnIndex) {
            this.sortOrder = this.sortOrder === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortOrder = 'asc';
            this.sortColumn = columnIndex;
        }
        
        // Sort rows
        const sortedRows = Array.from(rows).sort((rowA, rowB) => {
            const cellA = rowA.querySelectorAll('td')[columnIndex]?.textContent.trim() || '';
            const cellB = rowB.querySelectorAll('td')[columnIndex]?.textContent.trim() || '';
            
            // Try to parse as number
            const numA = parseFloat(cellA);
            const numB = parseFloat(cellB);
            
            let comparison = 0;
            if (!isNaN(numA) && !isNaN(numB)) {
                comparison = numA - numB;
            } else {
                comparison = cellA.localeCompare(cellB);
            }
            
            return this.sortOrder === 'asc' ? comparison : -comparison;
        });
        
        // Update header sort indicator
        header.classList.add(this.sortOrder === 'asc' ? 'sorted-asc' : 'sorted-desc');
        
        // Re-append sorted rows
        const tbody = table.querySelector('tbody');
        sortedRows.forEach(row => tbody.appendChild(row));
    }

    /**
     * Downloads the current report as CSV
     */
    downloadCSV() {
        if (!this.currentReport) return;
        
        try {
            const link = document.createElement('a');
            link.href = `/api/reports/${this.currentReport}/csv`;
            link.download = `${this.currentReport}_report.csv`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        } catch (error) {
            console.error('Failed to download CSV:', error);
            this.showError('Failed to download report');
        }
    }

    /**
     * Shows error message
     */
    showError(message) {
        this.reportContainer.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon">⚠</div>
                <div class="empty-state-title">Error</div>
                <div class="empty-state-message">${message}</div>
            </div>
        `;
    }
}

// Initialize the application when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    new ReportingApp();
});
