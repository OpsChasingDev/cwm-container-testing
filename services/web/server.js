/**
 * CWM Custom Reporting Server - Backend API
 * Serves static files and provides API endpoints for report discovery and download
 */

const express = require('express');
const path = require('path');
const fs = require('fs').promises;
const fsSync = require('fs');
const { createWriteStream } = require('fs');
const app = express();

const DATA_DIR = '/mnt/cwm-data';
const LOGS_DIR = '/mnt/cwm-logs';
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.static('html'));
app.use(express.static('css'));
app.use(express.static('js'));

// Logging utility
const log = (message) => {
    const timestamp = new Date().toLocaleString('en-US', {
        month: '2-digit',
        day: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false
    });
    const logMessage = `${timestamp} || INFO || ${message}`;
    console.log(logMessage);
    
    // Also write to log file if available
    writeToLogFile(logMessage);
};

const logError = (message) => {
    const timestamp = new Date().toLocaleString('en-US', {
        month: '2-digit',
        day: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false
    });
    const logMessage = `${timestamp} || ERROR || ${message}`;
    console.error(logMessage);
    
    // Also write to log file if available
    writeToLogFile(logMessage);
};

let logFilePath = null;

async function initializeLogging() {
    try {
        // Ensure logs directory exists
        if (!fsSync.existsSync(LOGS_DIR)) {
            fsSync.mkdirSync(LOGS_DIR, { recursive: true });
        }
        
        // Create log file with timestamp
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').split('T')[0] + '_' + 
                         new Date().toTimeString().split(' ')[0].replace(/:/g, '-');
        logFilePath = path.join(LOGS_DIR, `web_${timestamp}.log`);
        
        // Create empty log file
        await fs.writeFile(logFilePath, '');
        log('Web server logging initialized');
    } catch (error) {
        console.error('Failed to initialize logging:', error);
    }
}

function writeToLogFile(message) {
    if (logFilePath && fsSync.existsSync(logFilePath)) {
        try {
            const stream = createWriteStream(logFilePath, { flags: 'a' });
            stream.write(message + '\n');
            stream.end();
        } catch (error) {
            console.error('Failed to write to log file:', error);
        }
    }
}

/**
 * Converts app name from script convention to display name
 * Example: "appTimeSinceLastTimeEntry" -> "TimeSinceLastTimeEntry"
 */
function getDisplayName(appName) {
    // Remove "app" prefix if present
    if (appName.startsWith('app') && appName.length > 3) {
        return appName.substring(3);
    }
    return appName;
}

/**
 * Discovers available reports by scanning the data directory
 */
async function discoverReports() {
    try {
        const reports = [];
        
        // Check if data directory exists
        if (!fsSync.existsSync(DATA_DIR)) {
            log(`Data directory not found: ${DATA_DIR}`);
            return reports;
        }
        
        const entries = await fs.readdir(DATA_DIR, { withFileTypes: true });
        
        for (const entry of entries) {
            if (entry.isDirectory()) {
                const dirPath = path.join(DATA_DIR, entry.name);
                const files = await fs.readdir(dirPath);
                
                // Look for HTML files
                const htmlFile = files.find(f => f.endsWith('.html'));
                const csvFile = files.find(f => f.endsWith('.csv'));
                
                if (htmlFile) {
                    reports.push({
                        appName: entry.name,
                        displayName: getDisplayName(entry.name),
                        htmlFile: path.join(dirPath, htmlFile),
                        csvFile: csvFile ? path.join(dirPath, csvFile) : null
                    });
                }
            }
        }
        
        log(`Discovered ${reports.length} available reports`);
        return reports;
    } catch (error) {
        logError(`Failed to discover reports: ${error.message}`);
        return [];
    }
}

/**
 * API endpoint: Get available reports
 */
app.get('/api/reports', async (req, res) => {
    try {
        const reports = await discoverReports();
        const reportList = reports.map(r => ({
            appName: r.appName,
            displayName: r.displayName
        }));
        res.json(reportList);
    } catch (error) {
        logError(`GET /api/reports: ${error.message}`);
        res.status(500).json({ error: 'Failed to fetch reports' });
    }
});

/**
 * API endpoint: Get specific report HTML
 */
app.get('/api/reports/:appName', async (req, res) => {
    try {
        const { appName } = req.params;
        const reports = await discoverReports();
        const report = reports.find(r => r.appName === appName);
        
        if (!report || !report.htmlFile) {
            log(`Report not found: ${appName}`);
            return res.status(404).json({ error: 'Report not found' });
        }
        
        const htmlContent = await fs.readFile(report.htmlFile, 'utf-8');
        log(`Served HTML report: ${appName}`);
        res.setHeader('Content-Type', 'text/html');
        res.send(htmlContent);
    } catch (error) {
        logError(`GET /api/reports/:appName: ${error.message}`);
        res.status(500).json({ error: 'Failed to fetch report' });
    }
});

/**
 * API endpoint: Download report as CSV
 */
app.get('/api/reports/:appName/csv', async (req, res) => {
    try {
        const { appName } = req.params;
        const reports = await discoverReports();
        const report = reports.find(r => r.appName === appName);
        
        if (!report || !report.csvFile) {
            log(`CSV file not found for: ${appName}`);
            return res.status(404).json({ error: 'CSV file not found' });
        }
        
        const csvContent = await fs.readFile(report.csvFile, 'utf-8');
        log(`Served CSV download: ${appName}`);
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', `attachment; filename="${appName}_report.csv"`);
        res.send(csvContent);
    } catch (error) {
        logError(`GET /api/reports/:appName/csv: ${error.message}`);
        res.status(500).json({ error: 'Failed to download CSV' });
    }
});

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});

/**
 * Start server
 */
async function start() {
    await initializeLogging();
    
    app.listen(PORT, () => {
        log(`Web server started on port ${PORT}`);
        log('Watching for reports in: ' + DATA_DIR);
    });
}

start().catch(error => {
    logError(`Failed to start server: ${error.message}`);
    process.exit(1);
});
