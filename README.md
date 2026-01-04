# cwm-container-testing

Docker container with PowerShell Core and git that generates timestamped files.

## Features

- Lightweight Linux container based on PowerShell 7.4 (Debian)
- PowerShell Core and git pre-installed
- Automatically creates timestamped files every 5 seconds in `/opt/cwm-app/bin`

## Building the Container

```bash
docker build -t cwm-container-test .
```

## Running the Container

```bash
docker run -d --name cwm-test cwm-container-test
```

## Viewing Generated Files

```bash
docker exec cwm-test ls -la /opt/cwm-app/bin/
```

## Viewing Container Logs

```bash
docker logs cwm-test
```

## Stopping and Removing the Container

```bash
docker stop cwm-test
docker rm cwm-test
```

## Files

- **Dockerfile**: Container configuration with PowerShell Core and git
- **app.ps1**: PowerShell script that runs inside the container and generates timestamped files every 5 seconds