/**
 * CWM Custom Reporting Web Server
 * Serves static web UI and report files from mounted Azure File Share
 */

const express = require('express');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');
const app = express();

const PORT = process.env.PORT || 3000;
const DATA_DIR = '/mnt/cwm-data';
const LOGS_DIR = '/mnt/cwm-logs';

// Azure ACI Configuration
const AZURE_RESOURCE_GROUP = process.env.AZURE_RESOURCE_GROUP;
const AZURE_SUBSCRIPTION_ID = process.env.AZURE_SUBSCRIPTION_ID;
const ENVIRONMENT = process.env.ENVIRONMENT || 'production';

// Whitelist of allowed container names (report containers) with mapping to ACI container group names
// Maps app names (used in UI) to their corresponding Azure Container Instance container numbers
const APP_TO_CONTAINER_MAP = {
  'appReopenedTicket': 'app04',
  'appTimeSinceLastTimeEntry': 'app03',
  'appPOCOpenTicket': 'app05',
  'appAvgTimeEntryGap': 'app06',
  'appAvgTimeEntryDuration': 'app07',
  'appTicketsWorkedToday': 'app08',
  'appKeywordsLast7Days': 'app09',
};

const ALLOWED_CONTAINERS = Object.keys(APP_TO_CONTAINER_MAP);

// Helper function to get container group name
function getContainerGroupName(appName) {
  const containerNum = APP_TO_CONTAINER_MAP[appName];
  if (!containerNum) {
    throw new Error(`Unknown container mapping for app: ${appName}`);
  }
  const env = ENVIRONMENT === 'production' ? 'prod' : 'staging';
  return `cwm-${env}-${containerNum}`;
}

// Helper function to validate container name
function isValidContainer(containerName) {
  return ALLOWED_CONTAINERS.includes(containerName);
}

// Serve static files from public directory
app.use(express.static(path.join(__dirname, 'public')));

/**
 * Serve report files from mounted data directory
 * Frontend requests /report/filename -> server searches /mnt/cwm-data for file
 */
app.get('/report/:filename', (req, res) => {
  const { filename } = req.params;
  
  // Security: prevent directory traversal
  if (filename.includes('..')) {
    return res.status(400).send('Invalid filename');
  }

  // Search all subdirectories under /mnt/cwm-data for the requested file
  try {
    // Check if data directory exists
    if (!fs.existsSync(DATA_DIR)) {
      console.log(`Data directory not found: ${DATA_DIR}`);
      return res.status(404).send('Report not found');
    }

    // Get all subdirectories in /mnt/cwm-data
    const dirs = fs.readdirSync(DATA_DIR);
    
    for (const dir of dirs) {
      const filePath = path.join(DATA_DIR, dir, filename);
      
      // Check if file exists
      if (fs.existsSync(filePath)) {
        const stat = fs.statSync(filePath);
        
        // Security: only serve files, not directories
        if (stat.isFile()) {
          console.log(`Serving report: ${filename} from ${dir}`);
          
          // Set appropriate content type
          if (filename.endsWith('.html')) {
            res.setHeader('Content-Type', 'text/html; charset=utf-8');
          } else if (filename.endsWith('.csv')) {
            res.setHeader('Content-Type', 'text/csv; charset=utf-8');
            res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
          } else {
            res.setHeader('Content-Type', 'text/plain');
          }
          
          return res.sendFile(filePath);
        }
      }
    }
    
    // File not found in any subdirectory
    console.log(`Report not found: ${filename}`);
    res.status(404).send('Report not found');
    
  } catch (error) {
    console.error(`Error serving report: ${error.message}`);
    res.status(500).send('Error loading report');
  }
});

/**
 * Endpoint to provide CWM server configuration from environment variable
 */
app.get('/config/cwm-server', (req, res) => {
  const cwmServer = process.env.CWM_SERVER;
  if (!cwmServer) {
    return res.status(500).json({ error: 'CWM_SERVER environment variable not set' });
  }
  res.json({ cwmServer });
});

/**
 * Endpoint to provide environment configuration
 */
app.get('/config/environment', (req, res) => {
  const environment = process.env.ENVIRONMENT || 'production';
  res.json({ environment });
});

/**
 * Endpoint to provide ticketing boards configuration from environment variable
 */
app.get('/config/ticketing-boards', (req, res) => {
  const ticketingBoardsStr = process.env.TICKETING_BOARDS || '';
  let boards = [];
  
  if (ticketingBoardsStr) {
    // Parse comma-separated values and trim whitespace
    boards = ticketingBoardsStr.split(',').map(board => board.trim()).filter(board => board.length > 0);
  }
  
  res.json({ boards });
});

/**
 * Serve latest log file for a specific container
 * Frontend requests /logs/containerName -> server finds latest log file and returns content
 */
app.get('/logs/:containerName', (req, res) => {
  const { containerName } = req.params;
  
  // Security: prevent directory traversal
  if (containerName.includes('..') || containerName.includes('/')) {
    return res.status(400).send('Invalid container name');
  }

  try {
    // Check if logs directory exists
    if (!fs.existsSync(LOGS_DIR)) {
      console.log(`Logs directory not found: ${LOGS_DIR}`);
      return res.status(404).json({ error: 'Logs directory not found' });
    }

    // Get all files in the logs directory
    const files = fs.readdirSync(LOGS_DIR);
    
    // Filter for log files matching the container name pattern: {containerName}_YYYY-MM-DD_HH-MM-SS.log
    const logFiles = files.filter(file => 
      file.startsWith(containerName) && file.endsWith('.log')
    );
    
    if (logFiles.length === 0) {
      console.log(`No log files found for container: ${containerName}`);
      return res.status(404).json({ error: `No log files found for container: ${containerName}` });
    }

    // Sort files to find the latest (most recent timestamp)
    // Assuming format: {containerName}_YYYY-MM-DD_HH-MM-SS.log
    const latestLogFile = logFiles.sort().pop();
    const logFilePath = path.join(LOGS_DIR, latestLogFile);
    
    // Read and return the log file content
    const logContent = fs.readFileSync(logFilePath, 'utf-8');
    
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.send(logContent);
    
    console.log(`Serving log file: ${latestLogFile} for container: ${containerName}`);
    
  } catch (error) {
    console.error(`Error serving log file: ${error.message}`);
    res.status(500).json({ error: 'Error loading log file' });
  }
});

/**
 * Download endpoint for log files
 * Frontend requests /download-logs/containerName -> server returns log file as downloadable attachment
 */
app.get('/download-logs/:containerName', (req, res) => {
  const { containerName } = req.params;
  
  // Security: prevent directory traversal
  if (containerName.includes('..') || containerName.includes('/')) {
    return res.status(400).send('Invalid container name');
  }

  try {
    // Check if logs directory exists
    if (!fs.existsSync(LOGS_DIR)) {
      console.log(`Logs directory not found: ${LOGS_DIR}`);
      return res.status(404).send('Logs directory not found');
    }

    // Get all files in the logs directory
    const files = fs.readdirSync(LOGS_DIR);
    
    // Filter for log files matching the container name pattern: {containerName}_YYYY-MM-DD_HH-MM-SS.log
    const logFiles = files.filter(file => 
      file.startsWith(containerName) && file.endsWith('.log')
    );
    
    if (logFiles.length === 0) {
      console.log(`No log files found for container: ${containerName}`);
      return res.status(404).send(`No log files found for container: ${containerName}`);
    }

    // Sort files to find the latest (most recent timestamp)
    // Assuming format: {containerName}_YYYY-MM-DD_HH-MM-SS.log
    const latestLogFile = logFiles.sort().pop();
    const logFilePath = path.join(LOGS_DIR, latestLogFile);
    
    // Set headers for file download
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${latestLogFile}"`);
    
    // Send the file
    res.sendFile(logFilePath);
    
    console.log(`Downloading log file: ${latestLogFile} for container: ${containerName}`);
    
  } catch (error) {
    console.error(`Error downloading log file: ${error.message}`);
    res.status(500).send('Error downloading log file');
  }
});

/**
 * Get container group power state
 * Frontend requests /container-status/containerName -> returns {state: 'running'|'stopped', lastModified: timestamp}
 */
app.get('/container-status/:containerName', (req, res) => {
  const { containerName } = req.params;
  
  // Validate container name
  if (!isValidContainer(containerName)) {
    return res.status(400).json({ error: 'Invalid container name' });
  }

  // Check prerequisites
  if (!AZURE_RESOURCE_GROUP || !AZURE_SUBSCRIPTION_ID) {
    console.error('Azure configuration missing');
    return res.status(500).json({ error: 'Azure configuration not available' });
  }

  try {
    const groupName = getContainerGroupName(containerName);
    
    // Query container group state using Azure CLI
    const command = `az container show --resource-group ${AZURE_RESOURCE_GROUP} --name ${groupName} --query "containers[0].instanceView.currentState.state" --output tsv`;
    
    const state = execSync(command, { encoding: 'utf-8' }).trim().toLowerCase();
    
    // State will be 'running', 'waiting', 'terminated', etc.
    const isRunning = state === 'running';
    
    res.json({ 
      state: isRunning ? 'running' : 'stopped',
      containerGroup: groupName,
      actualState: state,
      timestamp: new Date().toISOString()
    });
    
    console.log(`Container status query: ${groupName} -> ${state}`);
    
  } catch (error) {
    console.error(`Error querying container status for ${containerName}: ${error.message}`);
    // Return error state if unable to query
    res.status(500).json({ 
      state: 'unknown',
      error: 'Unable to query container status',
      details: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * Control container group power state (start/stop)
 * Frontend sends POST /container-action/containerName with {action: 'start'|'stop'}
 */
app.post('/container-action/:containerName', express.json(), (req, res) => {
  const { containerName } = req.params;
  const { action } = req.body;
  
  // Validate inputs
  if (!isValidContainer(containerName)) {
    return res.status(400).json({ error: 'Invalid container name' });
  }
  
  if (!['start', 'stop'].includes(action)) {
    return res.status(400).json({ error: 'Invalid action. Must be "start" or "stop"' });
  }

  // Check prerequisites
  if (!AZURE_RESOURCE_GROUP || !AZURE_SUBSCRIPTION_ID) {
    console.error('Azure configuration missing');
    return res.status(500).json({ error: 'Azure configuration not available' });
  }

  try {
    const groupName = getContainerGroupName(containerName);
    
    // Execute start or stop action
    if (action === 'start') {
      execSync(`az container start --resource-group ${AZURE_RESOURCE_GROUP} --name ${groupName}`, { encoding: 'utf-8' });
      console.log(`Container started: ${groupName}`);
      res.json({ success: true, action: 'start', containerGroup: groupName, timestamp: new Date().toISOString() });
    } else {
      execSync(`az container stop --resource-group ${AZURE_RESOURCE_GROUP} --name ${groupName}`, { encoding: 'utf-8' });
      console.log(`Container stopped: ${groupName}`);
      res.json({ success: true, action: 'stop', containerGroup: groupName, timestamp: new Date().toISOString() });
    }
    
  } catch (error) {
    console.error(`Error controlling container: ${error.message}`);
    res.status(500).json({ 
      error: 'Failed to control container',
      details: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * Health check endpoint for container orchestration
 */
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

/**
 * Start server
 */
app.listen(PORT, () => {
  console.log(`CWM Custom Reporting Web Server listening on port ${PORT}`);
  console.log(`Serving static files from: ${path.join(__dirname, 'public')}`);
  console.log(`Reading reports from: ${DATA_DIR}`);
  console.log(`Reading logs from: ${LOGS_DIR}`);
  console.log(`Health check available at: http://localhost:${PORT}/health`);
});
