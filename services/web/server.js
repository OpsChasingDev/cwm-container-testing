/**
 * CWM Custom Reporting Web Server
 * Serves static web UI and report files from mounted Azure File Share
 */

const express = require('express');
const path = require('path');
const fs = require('fs');
const { ContainerInstanceManagementClient } = require('@azure/arm-containerinstance');
const { DefaultAzureCredential } = require('@azure/identity');
const app = express();

const PORT = process.env.PORT || 3000;
const DATA_DIR = '/mnt/cwm-data';
const LOGS_DIR = '/mnt/cwm-logs';

// Azure ACI Configuration
const AZURE_RESOURCE_GROUP = process.env.AZURE_RESOURCE_GROUP;
const AZURE_SUBSCRIPTION_ID = process.env.AZURE_SUBSCRIPTION_ID;
const ENVIRONMENT = process.env.ENVIRONMENT || 'production';

// Log Azure configuration at startup for debugging
console.log('=== Azure Configuration at Startup ===');
console.log(`AZURE_RESOURCE_GROUP: ${AZURE_RESOURCE_GROUP || 'NOT SET'}`);
console.log(`AZURE_SUBSCRIPTION_ID: ${AZURE_SUBSCRIPTION_ID || 'NOT SET'}`);
console.log(`ENVIRONMENT: ${ENVIRONMENT}`);
console.log(`AZURE_CREDENTIALS_B64: ${process.env.AZURE_CREDENTIALS_B64 ? 'SET (base64)' : 'NOT SET'}`);
console.log(`AZURE_CREDENTIALS: ${process.env.AZURE_CREDENTIALS ? 'SET (raw)' : 'NOT SET'}`);
console.log('========================================');

// Parse and set Azure credentials from AZURE_CREDENTIALS secret (or base64-encoded version)
// DefaultAzureCredential will use these environment variables for authentication
let credentialsJson = process.env.AZURE_CREDENTIALS;

// If credentials are base64 encoded (from deployment), decode them
if (process.env.AZURE_CREDENTIALS_B64) {
  try {
    credentialsJson = Buffer.from(process.env.AZURE_CREDENTIALS_B64, 'base64').toString('utf-8');
    console.log('Azure credentials decoded from AZURE_CREDENTIALS_B64');
  } catch (error) {
    console.error('Failed to decode AZURE_CREDENTIALS_B64:', error.message);
  }
}

// Parse and set credentials
if (credentialsJson) {
  try {
    const azureCredentials = JSON.parse(credentialsJson);
    process.env.AZURE_CLIENT_ID = azureCredentials.clientId;
    process.env.AZURE_CLIENT_SECRET = azureCredentials.clientSecret;
    process.env.AZURE_TENANT_ID = azureCredentials.tenantId;
    console.log('Azure credentials loaded from AZURE_CREDENTIALS');
  } catch (error) {
    console.error('Failed to parse Azure credentials:', error.message);
  }
}

// Initialize Azure clients with DefaultAzureCredential
// This automatically uses the service principal credentials set above
const credential = new DefaultAzureCredential();
const containerClient = new ContainerInstanceManagementClient(credential, AZURE_SUBSCRIPTION_ID);

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
  'appTicketsWorkedLastDays_30': 'app1'
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
    // Parse comma-separated values and trim whitespace and remove leading and trailing apostrophes
    boards = ticketingBoardsStr.split(',').map(board => board.trim().replace(/^'+|'+$/g, '')).filter(board => board.length > 0);
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
 * Get all container statuses
 * Frontend requests /all-container-status -> returns {[containerName]: {state, actualState, ...}}
 */
app.get('/all-container-status', async (req, res) => {
  if (!AZURE_RESOURCE_GROUP || !AZURE_SUBSCRIPTION_ID) {
    console.error('Azure configuration missing for all container status query');
    return res.status(500).json({ error: 'Azure configuration not available' });
  }

  const statuses = {};
  const containerPromises = [];

  // Query status for each container in parallel
  for (const containerName of ALLOWED_CONTAINERS) {
    containerPromises.push(
      (async () => {
        try {
          const groupName = getContainerGroupName(containerName);
          const containerGroup = await containerClient.containerGroups.get(AZURE_RESOURCE_GROUP, groupName);
          const rawState = containerGroup.containers[0]?.instanceView?.currentState?.state || 'unknown';
          const state = rawState.toLowerCase();
          const isRunning = state === 'running';
          
          statuses[containerName] = {
            state: isRunning ? 'running' : 'stopped',
            containerGroup: groupName,
            actualState: state,
            rawState: rawState,
            timestamp: new Date().toISOString()
          };
          console.log(`Container ${groupName} status: ${state}`);
        } catch (error) {
          console.error(`Error querying status for ${containerName}: ${error.message}`);
          statuses[containerName] = {
            state: 'unknown',
            actualState: 'unknown',
            error: error.message,
            timestamp: new Date().toISOString()
          };
        }
      })()
    );
  }

  // Wait for all queries to complete
  await Promise.all(containerPromises);
  res.json(statuses);
});


app.get('/container-status/:containerName', async (req, res) => {
  const { containerName } = req.params;
  
  // Validate container name
  if (!isValidContainer(containerName)) {
    return res.status(400).json({ error: 'Invalid container name' });
  }

  // Check prerequisites
  if (!AZURE_RESOURCE_GROUP || !AZURE_SUBSCRIPTION_ID) {
    console.error('Azure configuration missing for container status query:');
    console.error(`  AZURE_RESOURCE_GROUP: ${AZURE_RESOURCE_GROUP || 'NOT SET'}`);
    console.error(`  AZURE_SUBSCRIPTION_ID: ${AZURE_SUBSCRIPTION_ID || 'NOT SET'}`);
    return res.status(500).json({ 
      error: 'Azure configuration not available',
      details: {
        resourceGroup: AZURE_RESOURCE_GROUP ? 'SET' : 'MISSING',
        subscriptionId: AZURE_SUBSCRIPTION_ID ? 'SET' : 'MISSING'
      }
    });
  }

  try {
    const groupName = getContainerGroupName(containerName);
    
    console.log(`Querying container status using Azure SDK for: ${groupName}`);
    
    // Query container group state using Azure SDK
    const containerGroup = await containerClient.containerGroups.get(AZURE_RESOURCE_GROUP, groupName);
    
    // Get the state from the container's instance view (Azure SDK returns 'Running' or 'Stopped' with capital letters)
    const rawState = containerGroup.containers[0]?.instanceView?.currentState?.state || 'unknown';
    const state = rawState.toLowerCase();
    
    console.log(`Container ${groupName} raw state: ${rawState}, normalized: ${state}`);
    
    // State will be 'running', 'waiting', 'terminated', etc.
    const isRunning = state === 'running';
    
    res.json({ 
      state: isRunning ? 'running' : 'stopped',
      containerGroup: groupName,
      actualState: state,  // normalized lowercase
      rawState: rawState,   // raw state from Azure SDK
      timestamp: new Date().toISOString()
    });
    
    console.log(`Container status query: ${groupName} -> ${state}`);
    
  } catch (error) {
    console.error(`Error querying container status for ${containerName}: ${error.message}`);
    console.error(`Stack: ${error.stack}`);
    // Return error state if unable to query
    res.status(500).json({ 
      state: 'unknown',
      error: 'Unable to query container status',
      details: error.message,
      containerGroup: `cwm-${ENVIRONMENT === 'production' ? 'prod' : 'staging'}-${APP_TO_CONTAINER_MAP[containerName]}`,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * Control container group power state (start/stop)
 * Frontend sends POST /container-action/containerName with {action: 'start'|'stop'}
 */
app.post('/container-action/:containerName', express.json(), async (req, res) => {
  const { containerName } = req.params;
  const { action } = req.body;
  
  console.log(`POST /container-action - Received containerName: "${containerName}", action: "${action}"`);
  console.log(`POST /container-action - ALLOWED_CONTAINERS: ${JSON.stringify(ALLOWED_CONTAINERS)}`);
  console.log(`POST /container-action - isValidContainer result: ${isValidContainer(containerName)}`);
  
  // Validate inputs
  if (!isValidContainer(containerName)) {
    console.error(`POST /container-action - Invalid container name: "${containerName}"`);
    return res.status(400).json({ error: 'Invalid container name', receivedContainerName: containerName, allowedContainers: ALLOWED_CONTAINERS });
  }
  
  if (!['start', 'stop'].includes(action)) {
    return res.status(400).json({ error: 'Invalid action. Must be "start" or "stop"' });
  }

  // Check prerequisites
  if (!AZURE_RESOURCE_GROUP || !AZURE_SUBSCRIPTION_ID) {
    console.error('Azure configuration missing for container action:');
    console.error(`  AZURE_RESOURCE_GROUP: ${AZURE_RESOURCE_GROUP || 'NOT SET'}`);
    console.error(`  AZURE_SUBSCRIPTION_ID: ${AZURE_SUBSCRIPTION_ID || 'NOT SET'}`);
    return res.status(500).json({ 
      error: 'Azure configuration not available',
      details: {
        resourceGroup: AZURE_RESOURCE_GROUP ? 'SET' : 'MISSING',
        subscriptionId: AZURE_SUBSCRIPTION_ID ? 'SET' : 'MISSING'
      }
    });
  }

  try {
    const groupName = getContainerGroupName(containerName);
    
    console.log(`Executing ${action} on container using Azure SDK: ${groupName}`);
    
    // Execute start or stop action using Azure SDK
    if (action === 'start') {
      // Start uses Long Running Operations - need to poll
      const poller = await containerClient.containerGroups.beginStart(AZURE_RESOURCE_GROUP, groupName);
      await poller.pollUntilDone();
      console.log(`Container started: ${groupName}`);
      res.json({ success: true, action: 'start', containerGroup: groupName, timestamp: new Date().toISOString() });
    } else {
      // Stop is a direct operation (no Long Running Operation)
      await containerClient.containerGroups.stop(AZURE_RESOURCE_GROUP, groupName);
      console.log(`Container stopped: ${groupName}`);
      res.json({ success: true, action: 'stop', containerGroup: groupName, timestamp: new Date().toISOString() });
    }
    
  } catch (error) {
    console.error(`Error controlling container: ${error.message}`);
    console.error(`Stack: ${error.stack}`);
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
