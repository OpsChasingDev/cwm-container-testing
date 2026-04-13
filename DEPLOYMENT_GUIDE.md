# CWM Custom Reporting — Deployment Guide

A step-by-step guide for deploying the CWM Custom Reporting platform into a new GitHub repository, a new Azure subscription and resource group, and fronting it with Azure App Proxy and Entra authentication using a static public IP address.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Part 1 — Azure Subscription and Resource Group (15–20 min)](#part-1--azure-subscription-and-resource-group-1520-min)
- [Part 2 — Azure Container Registry (5–10 min)](#part-2--azure-container-registry-510-min)
- [Part 3 — Storage Account and File Shares (10–15 min)](#part-3--storage-account-and-file-shares-1015-min)
- [Part 4 — Static Public IP Address (5–10 min)](#part-4--static-public-ip-address-510-min)
- [Part 5 — Azure DNS Zone (10–15 min)](#part-5--azure-dns-zone-1015-min)
- [Part 6 — Service Principal (10–15 min)](#part-6--service-principal-1015-min)
- [Part 7 — Azure App Proxy and Entra Authentication (30–45 min)](#part-7--azure-app-proxy-and-entra-authentication-3045-min)
- [Part 8 — GitHub Repository Setup (15–20 min)](#part-8--github-repository-setup-1520-min)
- [Part 9 — Workflow Modifications for Static IP (10–15 min)](#part-9--workflow-modifications-for-static-ip-1015-min)
- [Part 10 — Initial Deployment and Validation (15–20 min)](#part-10--initial-deployment-and-validation-1520-min)
- [Time Estimate Summary](#time-estimate-summary)
- [Ongoing Maintenance](#ongoing-maintenance)

---

## Prerequisites

Before starting, confirm you have the following:

- A GitHub organization account with permissions to create repositories and configure secrets
- An Azure tenant with Global Administrator or Privileged Role Administrator access
- An Azure subscription (or the ability to create one) in the organization's tenant
- Microsoft Entra ID P1 or P2 licensing (required for Azure App Proxy)
- ConnectWise Manage API credentials (Company ID, Server URL, Public Key, Private Key, Client ID)
- Azure CLI installed locally (`az` command) and authenticated
- A domain name or subdomain you control for DNS (e.g., `cwm-reporting.yourcompany.com`)

---

## Part 1 — Azure Subscription and Resource Group (15–20 min)

### 1.1 Create the Azure Subscription

> Skip this step if you are using an existing subscription.

1. Navigate to the Azure Portal → **Subscriptions** → **+ Add**.
2. Select the appropriate offer (e.g., Pay-As-You-Go or Enterprise Agreement).
3. Name the subscription (e.g., `CWM-Reporting-Sub`).
4. Assign it to the organization's Entra tenant.
5. Wait for the subscription to provision (typically under 5 minutes).

### 1.2 Create the Resource Group

```bash
az account set --subscription "<your-subscription-id>"

az group create \
  --name "rg-cwm-reporting" \
  --location "eastus"
```

Choose a region that supports Azure Container Instances. All subsequent resources will be created in this resource group and region.

---

## Part 2 — Azure Container Registry (5–10 min)

### 2.1 Create the ACR

```bash
az acr create \
  --resource-group "rg-cwm-reporting" \
  --name "cwmreportingacr" \
  --sku Basic \
  --admin-enabled true
```

> The ACR name must be globally unique, lowercase, and alphanumeric only.

### 2.2 Retrieve ACR Credentials

```bash
# Login server URL
az acr show \
  --name "cwmreportingacr" \
  --query loginServer \
  --output tsv

# Admin username and password
az acr credential show \
  --name "cwmreportingacr"
```

Record these values for GitHub secrets:

| Value | Used As |
|-------|---------|
| Login server (e.g., `cwmreportingacr.azurecr.io`) | `ACR_LOGIN_SERVER` |
| Admin username | `ACR_USERNAME` |
| Password (either password1 or password2) | `ACR_PASSWORD` |

---

## Part 3 — Storage Account and File Shares (10–15 min)

### 3.1 Create the Storage Account

```bash
az storage account create \
  --name "cwmreportingstorage" \
  --resource-group "rg-cwm-reporting" \
  --location "eastus" \
  --sku Standard_LRS \
  --kind StorageV2
```

> The storage account name must be globally unique, lowercase, alphanumeric, and between 3–24 characters.

### 3.2 Retrieve the Storage Account Key

```bash
az storage account keys list \
  --resource-group "rg-cwm-reporting" \
  --account-name "cwmreportingstorage" \
  --query "[0].value" \
  --output tsv
```

Record this value as `AZURE_STORAGE_ACCOUNT_KEY`.

### 3.3 Create the Azure File Shares

Five file shares are required (production data and logging, staging data and logging, plus shared branding):

```bash
STORAGE_KEY=$(az storage account keys list \
  --resource-group "rg-cwm-reporting" \
  --account-name "cwmreportingstorage" \
  --query "[0].value" \
  --output tsv)

# Production shares
az storage share create --name "cwm-prod-shared-data" \
  --account-name "cwmreportingstorage" --account-key "$STORAGE_KEY"

az storage share create --name "cwm-prod-shared-logging" \
  --account-name "cwmreportingstorage" --account-key "$STORAGE_KEY"

# Staging shares
az storage share create --name "cwm-staging-shared-data" \
  --account-name "cwmreportingstorage" --account-key "$STORAGE_KEY"

az storage share create --name "cwm-staging-shared-logging" \
  --account-name "cwmreportingstorage" --account-key "$STORAGE_KEY"

# Shared branding share (used by both environments)
az storage share create --name "branding" \
  --account-name "cwmreportingstorage" --account-key "$STORAGE_KEY"
```

### 3.4 Upload Branding Assets

Upload `icon.png` and `banner.png` to the `branding` file share:

```bash
az storage file upload --share-name "branding" \
  --account-name "cwmreportingstorage" --account-key "$STORAGE_KEY" \
  --source "./icon.png"

az storage file upload --share-name "branding" \
  --account-name "cwmreportingstorage" --account-key "$STORAGE_KEY" \
  --source "./banner.png"
```

### File Share Summary

| File Share | Mount Path | Purpose |
|------------|-----------|---------|
| `cwm-prod-shared-data` | `/mnt/cwm-data` | Production report output (CSV, HTML) |
| `cwm-prod-shared-logging` | `/mnt/cwm-logs` | Production application logs |
| `cwm-staging-shared-data` | `/mnt/cwm-data` | Staging report output (CSV, HTML) |
| `cwm-staging-shared-logging` | `/mnt/cwm-logs` | Staging application logs |
| `branding` | `/mnt/cwm-branding` | Shared branding assets (`icon.png`, `banner.png`) |

---

## Part 4 — Static Public IP Address (5–10 min)

Since ACI container groups are deleted and recreated on each deployment, the public IP normally changes. To maintain a static IP, deploy an intermediary resource such as an Azure Application Gateway.

### 4.1 Create a Static Public IP

```bash
az network public-ip create \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-web-public-ip" \
  --sku Standard \
  --allocation-method Static \
  --location "eastus"
```

### 4.2 Retrieve the Static IP

```bash
az network public-ip show \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-web-public-ip" \
  --query ipAddress \
  --output tsv
```

Record this IP address. It will be used for DNS records and App Proxy configuration.

### 4.3 Network Integration for ACI with Static IP

To assign the static IP to ACI, deploy the web container into a virtual network and front it with an Application Gateway.

#### Create a VNet and Subnets

```bash
az network vnet create \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-vnet" \
  --address-prefix "10.0.0.0/16" \
  --subnet-name "appgw-subnet" \
  --subnet-prefix "10.0.1.0/24"

az network vnet subnet create \
  --resource-group "rg-cwm-reporting" \
  --vnet-name "cwm-vnet" \
  --name "aci-subnet" \
  --address-prefix "10.0.2.0/24" \
  --delegations "Microsoft.ContainerInstance/containerGroups"
```

#### Create the Application Gateway

```bash
az network application-gateway create \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-appgw" \
  --sku Standard_v2 \
  --capacity 1 \
  --vnet-name "cwm-vnet" \
  --subnet "appgw-subnet" \
  --public-ip-address "cwm-web-public-ip" \
  --frontend-port 80 \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --servers "10.0.2.4"
```

> The `--servers` value (`10.0.2.4`) is a placeholder for the ACI container's private IP on the VNet. After deploying the web container for the first time, retrieve the actual private IP and update the Application Gateway backend pool accordingly (see [Part 9.2](#92-remove-the-dns-update-step)).

The static public IP (`cwm-web-public-ip`) is what your DNS and App Proxy will point to, and it remains stable across deployments.

> When using VNet-integrated ACI, the `deploy-web.yml` workflow must be updated. See [Part 9](#part-9--workflow-modifications-for-static-ip-1015-min) for details.

---

## Part 5 — Azure DNS Zone (10–15 min)

### 5.1 Create the DNS Zone

```bash
az network dns zone create \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-reporting.yourcompany.com"
```

### 5.2 Create A Records Pointing to the Static IP

```bash
STATIC_IP=$(az network public-ip show \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-web-public-ip" \
  --query ipAddress \
  --output tsv)

# Production — root record
az network dns record-set a add-record \
  --resource-group "rg-cwm-reporting" \
  --zone-name "cwm-reporting.yourcompany.com" \
  --record-set-name "@" \
  --ipv4-address "$STATIC_IP"

# Staging — subdomain record
az network dns record-set a add-record \
  --resource-group "rg-cwm-reporting" \
  --zone-name "cwm-reporting.yourcompany.com" \
  --record-set-name "staging" \
  --ipv4-address "$STATIC_IP"
```

### 5.3 Configure Domain Registrar NS Delegation

From the DNS zone output, copy the four Azure nameservers and add them as NS records at your domain registrar for the subdomain `cwm-reporting.yourcompany.com`.

```bash
az network dns zone show \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-reporting.yourcompany.com" \
  --query nameServers \
  --output tsv
```

> DNS propagation can take up to 48 hours, though it often completes in minutes.

---

## Part 6 — Service Principal (10–15 min)

The application needs a service principal for two purposes:

1. **GitHub Actions** — to deploy containers, manage ACI, and update DNS records.
2. **Web container runtime** — to start and stop ACI container groups via the Azure SDK.

### 6.1 Create the Service Principal

```bash
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

az ad sp create-for-rbac \
  --name "sp-cwm-reporting-cicd" \
  --role Contributor \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-cwm-reporting" \
  --sdk-auth
```

This outputs a JSON object. Save the entire output — it becomes the `AZURE_CREDENTIALS` GitHub secret:

```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  ...
}
```

### 6.2 Assign Additional Role for DNS (if needed)

If your DNS zone is in the same resource group, the Contributor role already covers it. If the DNS zone is in a different resource group, add:

```bash
az role assignment create \
  --assignee "<clientId-from-above>" \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/<dns-resource-group-name>"
```

---

## Part 7 — Azure App Proxy and Entra Authentication (30–45 min)

Azure App Proxy ensures employees must authenticate with their company Entra (Azure AD) accounts before accessing the web dashboard.

### 7.1 Prerequisites

- **Microsoft Entra ID P1 or P2 license** — required for Application Proxy.
- At least one **Application Proxy connector** installed on a Windows Server that has line-of-sight to the internet.

### 7.2 Install the App Proxy Connector (10–15 min)

1. In the Azure Portal, go to **Entra ID** → **Application proxy** → **Download connector service**.
2. Install the connector on a Windows Server (2016 or later) that can reach the internet.
3. Sign in with a Global Administrator account during setup.
4. Verify the connector appears as **Active** in the portal.

### 7.3 Register the Enterprise Application

1. In the Azure Portal, go to **Entra ID** → **Enterprise applications** → **+ New application** → **Create your own application**.
2. Name it `CWM Custom Reporting`.
3. Select **Configure Application Proxy for secure remote access to an on-premises application**.
4. Configure the following:

| Setting | Value |
|---------|-------|
| Internal URL | `http://<STATIC_IP>:80` |
| External URL | Auto-generated (e.g., `https://cwm-reporting-yourcompany.msappproxy.net`) or custom domain |
| Pre-authentication | Azure Active Directory |
| Connector group | Select the group containing your installed connector |

5. Click **Add**.

### 7.4 Configure Custom Domain (Optional but Recommended)

1. In the App Proxy application settings, go to **Application proxy**.
2. Set **External URL** to `https://cwm-reporting.yourcompany.com`.
3. Upload an SSL/TLS certificate (PFX) for `cwm-reporting.yourcompany.com`.
4. Add a CNAME record in your DNS zone:
   - **Name:** `cwm-reporting.yourcompany.com`
   - **Type:** `CNAME`
   - **Value:** `cwm-reporting-yourcompany.msappproxy.net`

### 7.5 Configure User Assignment

1. In the Enterprise application → **Users and groups** → **+ Add user/group**.
2. Assign the relevant Entra security groups or individual users who should have access.
3. In **Properties**, set **User assignment required?** to **Yes** to enforce access control.

### 7.6 Configure Single Sign-On (Optional)

1. In the Enterprise application → **Single sign-on**.
2. Since the backend web app does not natively support SSO, select **None** or **Header-based** if you want to pass Entra user claims via HTTP headers.

### 7.7 Conditional Access Policies (Optional but Recommended)

1. Go to **Entra ID** → **Security** → **Conditional Access** → **+ New policy**.
2. Create a policy requiring MFA or device compliance for access to the `CWM Custom Reporting` application.

---

## Part 8 — GitHub Repository Setup (15–20 min)

### 8.1 Create the Repository

1. In your GitHub organization, create a new **private** repository (e.g., `cwm-custom-reporting`).
2. Clone the source repository and push to the new one:

```bash
git clone https://github.com/OpsChasingDev/cwm-container-testing.git
cd cwm-container-testing
git remote set-url origin https://github.com/<your-org>/cwm-custom-reporting.git
git push -u origin main
```

### 8.2 Create the STAGING Branch

```bash
git checkout -b STAGING
git push -u origin STAGING
```

### 8.3 Create GitHub Environments

1. Go to **Settings** → **Environments**.
2. Create environment **`production`**.
   - Optionally add required reviewers for production deployments.
   - Optionally restrict to the `main` branch.
3. Create environment **`staging`**.
   - Optionally restrict to the `STAGING` branch.

### 8.4 Configure GitHub Actions Secrets

Go to **Settings** → **Secrets and variables** → **Actions** → **Secrets** and add each of the following:

| Secret | Value | Source |
|--------|-------|--------|
| `ACR_LOGIN_SERVER` | ACR login server URL (e.g., `cwmreportingacr.azurecr.io`) | [Part 2.2](#22-retrieve-acr-credentials) |
| `ACR_USERNAME` | ACR admin username | [Part 2.2](#22-retrieve-acr-credentials) |
| `ACR_PASSWORD` | ACR admin password | [Part 2.2](#22-retrieve-acr-credentials) |
| `AZURE_CREDENTIALS` | Full JSON output from `az ad sp create-for-rbac` | [Part 6.1](#61-create-the-service-principal) |
| `AZURE_LOCATION` | Azure region (e.g., `eastus`) | [Part 1.2](#12-create-the-resource-group) |
| `AZURE_RESOURCE_GROUP` | Resource group name (e.g., `rg-cwm-reporting`) | [Part 1.2](#12-create-the-resource-group) |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | [Part 1.1](#11-create-the-azure-subscription) |
| `AZURE_STORAGE_ACCOUNT_NAME` | Storage account name (e.g., `cwmreportingstorage`) | [Part 3.1](#31-create-the-storage-account) |
| `AZURE_STORAGE_ACCOUNT_KEY` | Storage account primary key | [Part 3.2](#32-retrieve-the-storage-account-key) |
| `CWM_CLIENTID` | ConnectWise Manage API Client ID | CWM admin |
| `CWM_COMPANY` | ConnectWise Manage Company ID | CWM admin |
| `CWM_PRIVATEKEY` | CWM API Private Key | CWM admin |
| `CWM_PUBLICKEY` | CWM API Public Key | CWM admin |
| `CWM_SERVER` | CWM Server URL (e.g., `na.myconnectwise.net`) | CWM admin |

### 8.5 Configure GitHub Actions Variables

Go to **Settings** → **Secrets and variables** → **Actions** → **Variables** and add:

| Variable | Value | Description |
|----------|-------|-------------|
| `TICKETING_BOARDS` | `Board 1,Board 2` | Comma-separated list of CWM service boards to report on |
| `UTC_TIME_ZONE` | `-5` | UTC offset for time calculations (e.g., `-5` for Eastern Time) |

---

## Part 9 — Workflow Modifications for Static IP (10–15 min)

Because the static IP is provided by an Application Gateway rather than by the ACI container group directly, the `deploy-web.yml` workflow needs changes.

### 9.1 Update the ACI Deployment YAML

In `.github/workflows/deploy-web.yml`, replace the `ipAddress` block in the generated ACI deployment YAML:

**Remove:**

```yaml
ipAddress:
  type: Public
  ports:
  - protocol: TCP
    port: 80
```

**Add:**

```yaml
subnetIds:
  - id: /subscriptions/<subscription-id>/resourceGroups/rg-cwm-reporting/providers/Microsoft.Network/virtualNetworks/cwm-vnet/subnets/aci-subnet
```

> Replace `<subscription-id>` with your Azure subscription ID from [Part 1.1](#11-create-the-azure-subscription).

### 9.2 Remove the DNS Update Step

Because DNS now points permanently to the static IP on the Application Gateway, remove the **Update Azure DNS Records** step from `deploy-web.yml`. Instead, after each deployment, update the Application Gateway backend pool to point to the new ACI private IP:

```bash
# Get the ACI container's private IP
ACI_PRIVATE_IP=$(az container show \
  --resource-group "rg-cwm-reporting" \
  --name "$CONTAINER_GROUP_NAME" \
  --query ipAddress.ip \
  --output tsv)

# Update the Application Gateway backend pool
az network application-gateway address-pool update \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "appGatewayBackendPool" \
  --servers "$ACI_PRIVATE_IP"
```

Add these commands to `deploy-web.yml` as a replacement for the removed DNS update step.

### 9.3 Update the DNS Zone Name

If keeping the DNS update step (e.g., for a non-static-IP setup), update the `DNS_ZONE_NAME` variable in `deploy-web.yml` to your new domain:

```yaml
DNS_ZONE_NAME=cwm-reporting.yourcompany.com
```

---

## Part 10 — Initial Deployment and Validation (15–20 min)

### 10.1 Trigger the First Deployment

1. Make a small commit (e.g., update the README) and push to `main`.
2. Alternatively, push changes to files matching the path filters for each workflow.

> All 8 workflows must run at least once to create all container groups: `deploy-web.yml` and `deploy-app03.yml` through `deploy-app09.yml`.

### 10.2 Verify All Workflows

1. In GitHub → **Actions**, confirm all 8 workflows complete successfully.
2. If any fail, check the logs for missing secrets or misconfiguration.

### 10.3 Verify Azure Resources

```bash
# List all container groups
az container list \
  --resource-group "rg-cwm-reporting" \
  --output table

# Check the web container status
az container show \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-prod-web" \
  --query instanceView.state

# Check an app container
az container show \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-prod-app03" \
  --query instanceView.state
```

### 10.4 Verify the Web Dashboard

1. Navigate to your App Proxy external URL (e.g., `https://cwm-reporting.yourcompany.com`).
2. You should be prompted to sign in with your Entra account.
3. After authentication, the CWM Custom Reporting dashboard should load.
4. Verify reports are populating (may take up to 2 minutes for the first reporting cycle).
5. Test CSV download, board filtering, and container power controls.

### 10.5 Verify File Shares Have Data

```bash
az storage file list \
  --share-name "cwm-prod-shared-data" \
  --account-name "cwmreportingstorage" \
  --account-key "$STORAGE_KEY" \
  --output table

az storage file list \
  --share-name "cwm-prod-shared-logging" \
  --account-name "cwmreportingstorage" \
  --account-key "$STORAGE_KEY" \
  --output table
```

---

## Time Estimate Summary

| Part | Task | Time |
|------|------|------|
| 1 | Azure Subscription and Resource Group | 15–20 min |
| 2 | Azure Container Registry | 5–10 min |
| 3 | Storage Account and File Shares | 10–15 min |
| 4 | Static Public IP and Networking | 5–10 min |
| 5 | Azure DNS Zone | 10–15 min |
| 6 | Service Principal | 10–15 min |
| 7 | Azure App Proxy and Entra Authentication | 30–45 min |
| 8 | GitHub Repository and Secrets | 15–20 min |
| 9 | Workflow Modifications | 10–15 min |
| 10 | Deployment and Validation | 15–20 min |
| | **Total** | **~2–3 hours** |

> DNS propagation ([Part 5.3](#53-configure-domain-registrar-ns-delegation)) can add additional wait time of up to 48 hours, though it typically resolves within minutes to a few hours.

---

## Ongoing Maintenance

- **ACR credentials** — Rotate the ACR admin password periodically and update the `ACR_PASSWORD` GitHub secret.
- **Service principal secret** — The client secret expires after one year by default. Set a calendar reminder to rotate it and update `AZURE_CREDENTIALS` in GitHub.
- **Storage account keys** — Rotate keys periodically and update `AZURE_STORAGE_ACCOUNT_KEY` in GitHub after rotation.
- **CWM API keys** — If ConnectWise keys are rotated, update all `CWM_*` secrets in GitHub.
- **App Proxy connector** — Keep the connector host patched and ensure connector auto-updates are enabled.
- **SSL certificates** — If using a custom domain on App Proxy, track certificate expiration and renew before it expires.
