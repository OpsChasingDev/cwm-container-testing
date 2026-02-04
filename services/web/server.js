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
  console.log(`Health check available at: http://localhost:${PORT}/health`);
});
