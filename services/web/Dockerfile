# Use the official nginx image as a base
FROM nginx:alpine

# Create the /mnt/cwm-data directory for mounting Azure Files
RUN mkdir -p /mnt/cwm-data

# Copy a simple health check script
RUN echo '#!/bin/sh\nset -e\ncurl -f http://localhost/health || exit 1' > /healthcheck.sh && \
    chmod +x /healthcheck.sh

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD /healthcheck.sh

# Default nginx command
CMD ["nginx", "-g", "daemon off;"]
