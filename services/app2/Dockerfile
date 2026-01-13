# Use the official PowerShell image (based on Debian slim - lightweight)
FROM mcr.microsoft.com/powershell:7.4-debian-11

# Install git
RUN apt-get update && \
    apt-get install -y git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create the application directory
RUN mkdir -p /opt/cwm-app/bin

# Copy shared modules
COPY shared/modules/ /opt/cwm-app/modules/
COPY shared/config/ /opt/cwm-app/config/

# Copy service-specific script
COPY services/app2/app2.ps1 /opt/cwm-app/bin/app2.ps1

# Make the script executable
RUN chmod +x /opt/cwm-app/bin/app2.ps1

# Set the working directory
WORKDIR /opt/cwm-app/bin

# Run the PowerShell script as the entry point
ENTRYPOINT ["pwsh", "/opt/cwm-app/bin/app2.ps1"]
