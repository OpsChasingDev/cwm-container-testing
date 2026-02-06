<<<<<<< HEAD
# Use the official nginx image as a base
FROM nginx:alpine
=======
# Use Node.js 18 Alpine as the base image
FROM node:18-alpine
>>>>>>> DEV

# Create the /mnt/cwm-data directory for mounting Azure Files
RUN mkdir -p /mnt/cwm-data

<<<<<<< HEAD
# Copy a simple health check script
RUN echo '#!/bin/sh\nset -e\ncurl -f http://localhost/health || exit 1' > /healthcheck.sh && \
    chmod +x /healthcheck.sh

# Expose port 80
EXPOSE 80
=======
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
>>>>>>> DEV

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD /healthcheck.sh

<<<<<<< HEAD
# Default nginx command
CMD ["nginx", "-g", "daemon off;"]
=======
# Start the server
CMD ["node", "server.js"]
>>>>>>> DEV
