/**
 * CWM Custom Reporting Web Server
 * Serves static web UI and report files from mounted Azure File Share
 */

const express = require('express');
const path = require('path');
const fs = require('fs');
const app = express();

const PORT = process.env.PORT || 3000;
const DATA_DIR = '/mnt/cwm-data';
const LOGS_DIR = '/mnt/cwm-logs';

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
