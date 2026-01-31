# Use the official Node.js image as a base
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy application files (paths are relative to build context root)
COPY services/web/package.json package.json
COPY services/web/server.js server.js
COPY services/web/html ./html
COPY services/web/css ./css
COPY services/web/js ./js

# Install dependencies
RUN npm install --production

# Expose port 3000 (internal) - will be mapped to 80 in container instances
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

# Start the application
CMD ["npm", "start"]
