# Use Node.js 18 Alpine as the base image
FROM node:18-alpine

# Create the /mnt/cwm-data directory for mounting Azure Files
RUN mkdir -p /mnt/cwm-data

# Create mount directory for reports
RUN mkdir -p /mnt/cwm-data

# Copy package files
COPY services/web/package.json .
COPY services/web/package-lock.json* .

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY services/web/server.js .

# Copy public files (static web content)
COPY services/web/public ./public

# Expose port 3000
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD /healthcheck.sh

# Start the server
CMD ["node", "server.js"]
