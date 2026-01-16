# Use the official PowerShell image (based on Debian slim - lightweight)
FROM mcr.microsoft.com/powershell:7.4-debian-11

# Create the application directory
RUN mkdir -p /opt/cwm-app/bin

# Copy shared modules
COPY shared/modules/ /opt/cwm-app/modules/
COPY shared/config/ /opt/cwm-app/config/

# Copy service-specific script
COPY services/appTimeSinceLastTimeEntry/appTimeSinceLastTimeEntry.ps1 /opt/cwm-app/bin/appTimeSinceLastTimeEntry.ps1

# Make the script executable
RUN chmod +x /opt/cwm-app/bin/appTimeSinceLastTimeEntry.ps1

# Set the working directory
WORKDIR /opt/cwm-app/bin

# Run the PowerShell script as the entry point
ENTRYPOINT ["pwsh", "/opt/cwm-app/bin/appTimeSinceLastTimeEntry.ps1"]
