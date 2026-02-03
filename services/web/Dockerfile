# Use the official Node.js image as a base
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Create directories for mounted volumes
RUN mkdir -p /mnt/cwm-data /mnt/cwm-logs

# Copy application files
COPY package.json package.json
COPY server.js server.js
COPY html ./html
COPY css ./css
COPY js ./js

# Install dependencies
RUN npm install --production

# Expose port 3000 (internal) - will be mapped to 80 in container instances
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

# Start the application
CMD ["npm", "start"]
