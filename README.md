# CWM Custom Reporting

A containerized ConnectWise Manage (CWM) custom reporting platform deployed on Azure Container Instances (ACI). The system runs multiple PowerShell-based report generation services alongside an Express.js web dashboard, providing real-time and daily reporting with interactive filtering, CSV exports, and container lifecycle management — all orchestrated through GitHub Actions CI/CD.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Report Generation Services](#report-generation-services)
- [Web Front-End](#web-front-end)
- [Azure Infrastructure](#azure-infrastructure)
- [CI/CD Pipeline](#cicd-pipeline)
- [GitHub Actions Secrets and Variables](#github-actions-secrets-and-variables)
- [Environments: Staging and Production](#environments-staging-and-production)
- [Unit Testing](#unit-testing)
- [Shared PowerShell Module Reference](#shared-powershell-module-reference)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                          GitHub Actions CI/CD                        │
│   (branch-based: main → production, STAGING → staging)               │
│   Test → Build Docker Image → Push to ACR → Deploy to ACI           │
└──────────────┬──────────────────────────────────────┬────────────────┘
               │                                      │
               ▼                                      ▼
┌──────────────────────────┐         ┌─────────────────────────────────┐
│  Azure Container Registry│         │    Azure Container Instances     │
│  (ACR)                   │         │                                 │
│  - cwm-web:prod/staging  │────────▶│  cwm-prod-web / cwm-staging-web │
│  - cwm-app03:prod/staging│         │  cwm-prod-app03..09             │
│  - cwm-app04:prod/staging│         │  cwm-staging-app03..09          │
│  ...                     │         │                                 │
└──────────────────────────┘         └─────────────┬───────────────────┘
                                                   │
                              ┌─────────────────┬──┴──────────────────┐
                              ▼                 ▼                     ▼
                   ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
                   │  Azure File Share│ │  Azure File Share│ │  Azure File Share│
                   │  cwm-shared-data │ │ cwm-shared-logging│ │cwm-shared-branding│
                   │  (CSV/HTML       │ │  (log files)     │ │ (icon.png,       │
                   │   reports)       │ │                  │ │  banner.png)     │
                   └──────────────────┘ └──────────────────┘ └──────────────────┘
```

The platform consists of three layers:

1. **Report Generation Services** (`app03`–`app09`) — PowerShell containers that query the ConnectWise Manage REST API on a 2-minute interval, generate CSV and HTML reports, and write them to a shared Azure File Share.
2. **Web Dashboard** (`web`) — A Node.js/Express server that reads reports from the shared file share, serves an interactive dashboard with filtering and export capabilities, and provides container power control via the Azure SDK.
3. **Shared Storage** — Azure File Shares provide persistent, cross-container access to report data, application logs, and branding assets.

All containers are deployed as individual Azure Container Instance groups, allowing independent scaling and lifecycle management.

---

## Repository Structure

```
cwm-container-testing/
├── .github/
│   └── workflows/                    # GitHub Actions CI/CD pipelines
│       ├── deploy-app03.yml          # Test, build, deploy app03
│       ├── deploy-app04.yml          # Test, build, deploy app04
│       ├── deploy-app05.yml          # Test, build, deploy app05
│       ├── deploy-app06.yml          # Test, build, deploy app06
│       ├── deploy-app07.yml          # Test, build, deploy app07
│       ├── deploy-app08.yml          # Test, build, deploy app08
│       ├── deploy-app09.yml          # Test, build, deploy app09
│       └── deploy-web.yml            # Build, deploy web dashboard
├── services/
│   ├── app03/                        # Time Since Last Time Entry Report
│   │   ├── Dockerfile
│   │   └── appTimeSinceLastTimeEntry.ps1
│   ├── app04/                        # Reopened Ticket Report
│   │   ├── Dockerfile
│   │   └── appReopenedTicket.ps1
│   ├── app05/                        # POC Open Ticket Report
│   │   ├── Dockerfile
│   │   └── appPOCOpenTicket.ps1
│   ├── app06/                        # Avg Time Entry Gap Report
│   │   ├── Dockerfile
│   │   └── appAvgTimeEntryGap.ps1
│   ├── app07/                        # Avg Time Entry Duration Report
│   │   ├── Dockerfile
│   │   └── appAvgTimeEntryDuration.ps1
│   ├── app08/                        # Tickets Worked Today Report
│   │   ├── Dockerfile
│   │   └── appTicketsWorkedToday.ps1
│   ├── app09/                        # Keywords Last 7 Days Report
│   │   ├── Dockerfile
│   │   └── appKeywordsLast7Days.ps1
│   └── web/                          # Web dashboard
│       ├── Dockerfile
│       ├── package.json
│       ├── server.js                 # Express.js API server
│       └── public/                   # Static front-end assets
│           ├── index.html            # Main dashboard page
│           ├── indexstyle.css         # Dashboard styles
│           ├── reportstyle.css       # Report table styles
│           ├── main.js               # Report loading, filtering, container control
│           ├── toggle_subsection.js  # Sidebar collapsible sections
│           └── data/
│               └── desc.json         # Report descriptions
├── shared/
│   └── modules/
│       └── CWMShared.psm1           # Shared PowerShell module
├── .dockerignore
├── .gitignore
└── README.md
```

---

## Report Generation Services

Each app container runs a PowerShell script inside a `mcr.microsoft.com/powershell:7.4-debian-11` Docker image. On startup, every app:

1. Imports the shared `CWMShared.psm1` module and the `ConnectWiseManageAPI` module (installed from PSGallery at build time).
2. Calls `Initialize-CWMApp` to create the data directory (`/mnt/cwm-data/<appName>/`) and log file (`/mnt/cwm-logs/<appName>_<timestamp>.log`).
3. Connects to the CWM REST API via `Connect-CWMAPI` using environment variables for credentials.
4. Enters a loop: generate a report, write CSV and HTML to the data share, sleep for 2 minutes, and repeat.

### Reports

| Service | Report Name | Description |
|---------|------------|-------------|
| `app03` | Time Since Last Time Entry | Top tickets with the longest time since anyone last entered time. |
| `app04` | Reopened Ticket | Currently open tickets that have been reopened at least once. |
| `app05` | POC Open Ticket | Open tickets whose primary contact has a CWM designation of Owner, POC, VIP, Primary Contact, or Decision Maker. |
| `app06` | Avg Time Entry Gap | Top tickets with the longest average gap (in days) between time entries. |
| `app07` | Avg Time Entry Duration | All open tickets with the average minutes spent per time entry. |
| `app08` | Tickets Worked Today | Per-technician stats on tickets worked in the current day. |
| `app09` | Keywords Last 7 Days | Top 20 most commonly used words in ticket summaries from the past 7 days. |

### Container Resources

| Component | CPU | Memory |
|-----------|-----|--------|
| App containers (`app03`–`app09`) | 0.5 cores | 0.5 GB |
| Web container (`web`) | 1.0 cores | 1.5 GB |

All app containers use a restart policy of `Always`, ensuring they automatically recover from failures.

---

## Web Front-End

The web dashboard is built with Express.js (server-side) and vanilla HTML/CSS/JavaScript (client-side), served from a Node.js 18 Alpine container.

### Dashboard Layout

The UI consists of:

- **Header** — Displays "CWM Custom Reporting" with optional branding banner.
- **Sidebar** — Contains report navigation, board filtering, and report descriptions.
- **Viewport** — Tabbed content area with **Data** and **Logs** tabs for the selected report.

### Key Features

#### Report Viewing
- Reports are organized into **Real-Time Reports** (refreshed every 2 minutes) and **Daily Reports** (refreshed once per day).
- Clicking a report name in the sidebar loads its HTML content into the viewport's Data tab.
- Report tables are rendered with sortable columns and styled with `reportstyle.css`.

#### Board Filtering
- The sidebar provides a **Select Boards** multi-select dropdown populated from the `TICKETING_BOARDS` configuration.
- Selecting one or more boards filters the displayed report data to only show tickets from those boards.
- The "All Boards" option resets the filter.

#### CSV Data Export
- A **Download CSV** button in the sidebar exports the currently displayed report as a CSV file.
- The download includes only the filtered data (if a board filter is active).

#### Application Logs
- Each report has a **Logs** tab that fetches and displays the most recent log file for that report's container from the shared logging file share.
- Logs are displayed in a monospace font with standardized formatting (`MM/dd/yyyy HH:mm:ss || TYPE || Message`).
- A **Download Logs** button allows downloading the raw log file.

#### Container Power Control
- Each real-time report has a ⚡ button for container lifecycle management.
- Clicking the button opens a confirmation modal showing the container's current state (Running / Stopped) and the available action (Start / Stop).
- Power control commands are sent to the server, which uses the Azure Container Instance Management SDK to start or stop the corresponding container group.
- Container status is polled periodically and displayed inline with visual indicators (green for running, red for stopped).
- A rate-limiting mechanism prevents rapid repeated actions on the same container.

#### Branding
- Custom branding assets (`icon.png`, `banner.png`) are served from the `/mnt/cwm-branding/` file share mount.
- The site favicon is loaded from `/branding/icon.png`.

### Server API Routes

| Route | Method | Description |
|-------|--------|-------------|
| `/` | GET | Serves the static dashboard UI |
| `/report/:filename` | GET | Streams a report file (HTML or CSV) from the data share |
| `/branding/:filename` | GET | Serves branding assets (PNG, SVG, JPEG) |
| `/config/cwm-server` | GET | Returns the CWM API server endpoint |
| `/config/environment` | GET | Returns the current deployment environment |
| `/config/ticketing-boards` | GET | Returns the configured ticketing board names |
| `/logs/:containerName` | GET | Returns the most recent log file for a container |
| `/download-logs/:containerName` | GET | Downloads the latest log file as an attachment |
| `/container-status/:containerName` | GET | Queries the Azure ACI container state |
| `/all-container-status` | GET | Queries the status of all app containers in parallel |
| `/container-action/:containerName` | POST | Starts or stops a container (body: `{"action": "start"\|"stop"}`) |
| `/health` | GET | Health check endpoint |

### UI-to-Container Mapping

The front-end uses friendly names that map to container service identifiers:

| UI Name | Service |
|---------|---------|
| `appTimeSinceLastTimeEntry` | `app03` |
| `appReopenedTicket` | `app04` |
| `appPOCOpenTicket` | `app05` |
| `appAvgTimeEntryGap` | `app06` |
| `appAvgTimeEntryDuration` | `app07` |
| `appTicketsWorkedToday` | `app08` |
| `appKeywordsLast7Days` | `app09` |

---

## Azure Infrastructure

### Azure Container Instances (ACI)

Each service runs as its own ACI container group, allowing independent deployment and lifecycle management. Container groups are created and updated via GitHub Actions using generated YAML deployment templates.

- **Production** groups: `cwm-prod-web`, `cwm-prod-app03` through `cwm-prod-app09`
- **Staging** groups: `cwm-staging-web`, `cwm-staging-app03` through `cwm-staging-app09`

### Azure Container Registry (ACR)

Docker images are built and pushed to ACR during the CI/CD pipeline. Each image is tagged with the environment prefix and commit SHA:

- `<acr-server>/cwm-web:prod` and `<acr-server>/cwm-web:prod-<sha>`
- `<acr-server>/cwm-app03:staging` and `<acr-server>/cwm-app03:staging-<sha>`

### Azure File Shares

Three Azure File Shares provide persistent storage shared across containers:

| File Share | Mount Path | Purpose |
|------------|-----------|---------|
| `cwm-<env>-shared-data` | `/mnt/cwm-data` | Report output files (CSV, HTML) organized by app subdirectory |
| `cwm-<env>-shared-logging` | `/mnt/cwm-logs` | Application log files with timestamps |
| `cwm-shared-branding` | `/mnt/cwm-branding` | Branding assets (`icon.png`, `banner.png`) shared across environments |

The data share uses per-app subdirectories (e.g., `/mnt/cwm-data/appTimeSinceLastTimeEntry/`) so the web server can locate and serve reports for each service independently.

### Azure DNS

The web dashboard is accessible via DNS records managed in an Azure DNS zone:

| Environment | Record | Domain |
|------------|--------|--------|
| Production | `@` (root) | `cwm-reporting.opschasingdev.com` |
| Staging | `staging` | `staging.cwm-reporting.opschasingdev.com` |

DNS records are updated automatically during deployment with a TTL of 60 seconds to point at the container group's public IP address.

---

## CI/CD Pipeline

### Workflow Structure

Each service has a dedicated GitHub Actions workflow file (e.g., `deploy-app03.yml`, `deploy-web.yml`). Workflows are triggered on pushes to `main` (production) or `STAGING` (staging) branches and are scoped by path filters so that only relevant changes trigger a given service's pipeline.

**Path Filters Example** (app03):
```yaml
paths:
  - 'services/app03/**'
  - 'shared/**'
  - '.github/workflows/deploy-app03.yml'
```

### Pipeline Stages

#### 1. Test (App containers only)

The test job validates the PowerShell code before building:

- **Module Import Validation** — Verifies that `CWMShared.psm1` can be imported and exports the expected functions (`New-CWMLog`, `Initialize-CWMApp`, etc.).
- **Script Syntax Check** — Parses the app's entry-point PowerShell script to detect syntax errors.
- **File Existence Check** — Confirms all required files (Dockerfile, scripts, modules) exist.
- **Environment Variable Check** — Verifies that required CWM API credential variables are defined in the workflow.

#### 2. Build

- Selects the environment (`production` or `staging`) based on the triggering branch.
- Sets up Docker Buildx for multi-platform builds.
- Authenticates to ACR and builds/pushes the Docker image with appropriate tags.

#### 3. Deploy

- Authenticates to Azure using a service principal (`AZURE_CREDENTIALS`).
- Generates an ACI deployment YAML with container configuration, environment variables, file share mounts, and resource limits.
- Deploys or updates the container group.
- For the web service: updates Azure DNS A records to point to the new container's public IP.

### Branch-to-Environment Mapping

| Branch | Environment | Container Prefix | DNS Record |
|--------|-------------|-------------------|------------|
| `main` | `production` | `cwm-prod-` | `@` (root) |
| `STAGING` | `staging` | `cwm-staging-` | `staging` |

---

## GitHub Actions Secrets and Variables

### Secrets

These are configured at the repository level in GitHub Settings → Secrets and Variables → Actions:

| Secret | Description |
|--------|-------------|
| `ACR_LOGIN_SERVER` | Azure Container Registry login server URL |
| `ACR_USERNAME` | ACR authentication username |
| `ACR_PASSWORD` | ACR authentication password |
| `AZURE_CREDENTIALS` | JSON service principal with `clientId`, `clientSecret`, `subscriptionId`, and `tenantId` |
| `AZURE_LOCATION` | Azure region for container deployment (e.g., `eastus`) |
| `AZURE_RESOURCE_GROUP` | Azure resource group containing ACI and storage resources |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription identifier |
| `AZURE_STORAGE_ACCOUNT_NAME` | Storage account hosting the Azure File Shares |
| `AZURE_STORAGE_ACCOUNT_KEY` | Access key for the storage account |
| `CWM_CLIENTID` | ConnectWise Manage API client ID |
| `CWM_COMPANY` | ConnectWise Manage company identifier |
| `CWM_PRIVATEKEY` | CWM API private key |
| `CWM_PUBLICKEY` | CWM API public key |
| `CWM_SERVER` | ConnectWise Manage server URL |

### Variables

These are configured at the repository level in GitHub Settings → Secrets and Variables → Actions → Variables:

| Variable | Description |
|----------|-------------|
| `TICKETING_BOARDS` | Comma-separated list of CWM service boards to query (e.g., `Service Board 1,Service Board 2`) |
| `UTC_TIME_ZONE` | UTC offset for time calculations (e.g., `-5` for Eastern Time) |

---

## Environments: Staging and Production

The project supports two fully isolated environments:

| Aspect | Production | Staging |
|--------|-----------|---------|
| Trigger branch | `main` | `STAGING` |
| GitHub environment | `production` | `staging` |
| Container group prefix | `cwm-prod-` | `cwm-staging-` |
| ACR image tag | `prod` / `prod-<sha>` | `staging` / `staging-<sha>` |
| Data file share | `cwm-prod-shared-data` | `cwm-staging-shared-data` |
| Logging file share | `cwm-prod-shared-logging` | `cwm-staging-shared-logging` |
| DNS record | `@` → `cwm-reporting.opschasingdev.com` | `staging` → `staging.cwm-reporting.opschasingdev.com` |

Both environments share the same branding file share (`cwm-shared-branding`) and the same set of GitHub Actions secrets and variables. Environment-specific values (like container group names and file share names) are derived dynamically in the workflow based on the branch.

---

## Unit Testing

Unit testing for the report generation scripts can be performed locally without deploying containers. Each app's initialization script (e.g., `appTimeSinceLastTimeEntry.ps1`) is designed for in-container execution with environment variables, but the core report logic and shared functions can be tested independently.

### Prerequisites

- **PowerShell 7+** installed locally.
- **ConnectWise Manage API credentials** (company, server URL, public key, private key, client ID).

### Steps

1. **Install the ConnectWiseManageAPI module** from the PowerShell Gallery:

   ```powershell
   Install-Module ConnectWiseManageAPI
   ```

2. **Import the shared module** from this repository:

   ```powershell
   Import-Module ./shared/modules/CWMShared.psm1
   ```

3. **Authenticate to the CWM REST API** using the interactive unit test helper:

   ```powershell
   Connect-CWMAPIUnitTest
   ```

   This command will prompt you for:
   - CWM Server URL
   - Company identifier
   - Public key
   - Private key (masked input)
   - Client ID (masked input)

   It then establishes an authenticated session and securely clears the credentials from memory.

4. **Run the report function** you want to test. For example, to test the Time Since Last Time Entry report logic:

   ```powershell
   # After authenticating, call the report function directly
   $tickets = Get-CWMFullTicket -Board "Your Board Name"
   $report = $tickets | ForEach-Object { Get-CWMTimeSinceLastTimeEntry -TicketID $_.id }
   ```

   Each app's initialization `.ps1` script is configured to run inside the container with environment-based configuration, but the individual job functions and shared module functions called within those scripts are designed to run outside the container environment once the above prerequisites are met.

### CI Test Validation

The GitHub Actions pipeline also performs automated testing for each app service before building. The test job validates:

- Successful import of `CWMShared.psm1` and its exported functions
- PowerShell script syntax correctness
- Existence of required files (Dockerfile, scripts, modules)
- Presence of required environment variable references in the deployment configuration

---

## Shared PowerShell Module Reference

The `shared/modules/CWMShared.psm1` module provides common functions used across all report generation services.

### Initialization Functions

| Function | Description |
|----------|-------------|
| `New-CWMLog -Type <Info\|Warning\|Error> -Message <string>` | Writes a timestamped, typed log entry to the console and to the log file (if initialized). Format: `MM/dd/yyyy HH:mm:ss \|\| TYPE \|\| Message` |
| `Initialize-CWMApp -AppName <string>` | Creates the app's data directory at `/mnt/cwm-data/<AppName>/` and a timestamped log file at `/mnt/cwm-logs/`. Returns the data path. |
| `Connect-CWMAPI` | Authenticates to the CWM REST API using environment variables (`CWM_Server`, `CWM_Company`, `CWM_PublicKey`, `CWM_PrivateKey`, `CWM_ClientID`). Used by containers. |
| `Connect-CWMAPIUnitTest` | Interactive authentication for local testing. Prompts for credentials, establishes a session, and securely clears credentials from memory. |

### Data Retrieval Functions

| Function | Description |
|----------|-------------|
| `Get-CWMFullTicket` | Retrieves tickets from the CWM API with filtering options for company, board, resource, and status. |
| `Get-CWMFullAuditTrail` | Fetches all audit trail entries for a ticket, handling pagination for results exceeding 1,000 records. |
| `Get-CWMTimeSinceLastTimeEntry` | Calculates the time elapsed since the last time entry was made on a ticket. |
| `Get-CWMReopenedTicketStatistics` | Analyzes audit trail data to determine how many times a ticket has been reopened. |
| `Get-CWMAvgTimeEntryGap` | Computes the average number of days between consecutive time entries on a ticket. |

### Utility Functions

| Function | Description |
|----------|-------------|
| `Construct-CWMCondition` | Builds CWM API query condition strings for filtering API requests. |
| `Construct-CWMCondition` | Builds CWM API query condition strings for filtering API requests. |