# CWM Custom Reporting — Deployment Guide

A step-by-step guide for deploying the CWM Custom Reporting platform into a new GitHub repository, a new Azure subscription and resource group, and fronting it with an Azure Application Gateway (with WAF) using a static public IP address.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Part 1 — Azure Subscription and Resource Group (15–20 min)](#part-1--azure-subscription-and-resource-group-1520-min)
- [Part 2 — Azure Container Registry (5–10 min)](#part-2--azure-container-registry-510-min)
- [Part 3 — Storage Account and File Shares (10–15 min)](#part-3--storage-account-and-file-shares-1015-min)
- [Part 4 — Static Public IP Address and Application Gateway (15–25 min)](#part-4--static-public-ip-address-and-application-gateway-1525-min)
- [Part 5 — DNS Configuration (5–10 min)](#part-5--dns-configuration-510-min)
- [Part 6 — Service Principal (10–15 min)](#part-6--service-principal-1015-min)
- [Part 7 — Application Gateway WAF and Access Protection (15–25 min)](#part-7--application-gateway-waf-and-access-protection-1525-min)
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
- ConnectWise Manage API credentials (Company ID, Server URL, Public Key, Private Key, Client ID)
- Azure CLI installed locally (`az` command) and authenticated
- An existing DNS domain you control with access to manage records in its authoritative name server (e.g., you will add an A record such as `reports.mycompany.com` to the `mycompany.com` DNS zone)

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

## Part 4 — Static Public IP Address and Application Gateway (15–25 min)

Since ACI container groups are deleted and recreated on each deployment, the public IP normally changes. To maintain a static IP and protect access to the web interface, deploy an Azure Application Gateway (with WAF) in front of the ACI container.

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

Record this IP address. It will be used for the DNS A record you create in your organization's existing DNS zone, and it remains stable across container redeployments.

### 4.3 Create a VNet and Subnets

The Application Gateway and ACI container each require their own subnet within a shared virtual network.

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

### 4.4 Create a WAF Policy

Create a Web Application Firewall policy that the Application Gateway will use to inspect and filter traffic.

```bash
az network application-gateway waf-policy create \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-waf-policy" \
  --location "eastus"
```

Enable the managed OWASP rule set:

```bash
az network application-gateway waf-policy managed-rule rule-set add \
  --resource-group "rg-cwm-reporting" \
  --policy-name "cwm-waf-policy" \
  --type "OWASP" \
  --version "3.2"
```

Set the WAF policy to **Prevention** mode (blocks malicious requests rather than just detecting them):

```bash
az network application-gateway waf-policy policy-setting update \
  --resource-group "rg-cwm-reporting" \
  --policy-name "cwm-waf-policy" \
  --mode Prevention \
  --state Enabled
```

### 4.5 Create the Application Gateway

Deploy the Application Gateway using the **WAF_v2** SKU, which provides both load-balancing and web application firewall capabilities.

```bash
az network application-gateway create \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-appgw" \
  --sku WAF_v2 \
  --capacity 1 \
  --vnet-name "cwm-vnet" \
  --subnet "appgw-subnet" \
  --public-ip-address "cwm-web-public-ip" \
  --frontend-port 80 \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --waf-policy "cwm-waf-policy" \
  --servers "10.0.2.4"
```

> The `--servers` value (`10.0.2.4`) is a placeholder for the ACI container's private IP on the VNet. After deploying the web container for the first time, retrieve the actual private IP and update the Application Gateway backend pool accordingly (see [Part 9.2](#92-update-the-application-gateway-backend-after-deployment)).

The static public IP (`cwm-web-public-ip`) is what your DNS A record will point to, and it remains stable across deployments.

> When using VNet-integrated ACI, the `deploy-web.yml` workflow must be updated. See [Part 9](#part-9--workflow-modifications-for-static-ip-1015-min) for details.

---

## Part 5 — DNS Configuration (5–10 min)

Because your organization already has an authoritative DNS zone for your domain (e.g., `mycompany.com`), you do **not** need to create a new Azure DNS zone or configure NS delegation. Instead, add an A record directly in your existing DNS name server so that traffic for your chosen hostname is directed to the Application Gateway's static public IP.

### 5.1 Choose a Hostname

Select a hostname under your existing domain for the reporting dashboard, for example:

- `reports.mycompany.com`
- `cwm-reporting.mycompany.com`

### 5.2 Add an A Record in Your Existing DNS Zone

Log in to wherever your organization manages DNS for the domain (e.g., your DNS hosting provider's control panel, an on-premises DNS server, or an existing Azure DNS zone) and create an A record:

| Record Type | Host / Name | Value | TTL |
|-------------|-------------|-------|-----|
| A | `reports` (relative to `mycompany.com`) | `<STATIC_IP>` | 300 (or your standard TTL) |

Replace `<STATIC_IP>` with the public IP from [Part 4.2](#42-retrieve-the-static-ip).

If you are managing the authoritative zone in Azure DNS, you can use the CLI:

```bash
STATIC_IP=$(az network public-ip show \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-web-public-ip" \
  --query ipAddress \
  --output tsv)

az network dns record-set a add-record \
  --resource-group "<dns-zone-resource-group>" \
  --zone-name "mycompany.com" \
  --record-set-name "reports" \
  --ipv4-address "$STATIC_IP"
```

> Replace `<dns-zone-resource-group>` with the resource group containing your existing Azure DNS zone, and adjust `mycompany.com` and `reports` to match your domain and chosen hostname.

If you also want a staging hostname (e.g., `reports-staging.mycompany.com`), add a second A record pointing to the same static IP:

| Record Type | Host / Name | Value | TTL |
|-------------|-------------|-------|-----|
| A | `reports-staging` (relative to `mycompany.com`) | `<STATIC_IP>` | 300 |

### 5.3 Verify DNS Resolution

After adding the record, verify it resolves correctly:

```bash
nslookup reports.mycompany.com
```

The response should return the static public IP assigned to the Application Gateway.

> DNS propagation depends on your DNS provider and TTL settings. It typically completes within minutes but can take up to the previous TTL value to expire from caches.

---

## Part 6 — Service Principal (10–15 min)

The application needs a service principal for two purposes:

1. **GitHub Actions** — to deploy containers, manage ACI, and update the Application Gateway backend pool.
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

### 6.2 Assign Additional Role for Network (if needed)

If your Application Gateway or VNet is in a different resource group than the ACI containers, assign the service principal the **Network Contributor** role on that resource group so the workflow can update the Application Gateway backend pool:

```bash
az role assignment create \
  --assignee "<clientId-from-above>" \
  --role "Network Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/<network-resource-group-name>"
```

---

## Part 7 — Application Gateway WAF and Access Protection (15–25 min)

The Application Gateway deployed in [Part 4](#part-4--static-public-ip-address-and-application-gateway-1525-min) already provides a Web Application Firewall (WAF) with the OWASP managed rule set. This section covers additional access restrictions you should configure to protect the web interface.

### 7.1 Restrict Access by Source IP (Recommended)

Create a WAF custom rule to allow traffic only from your organization's known public IP ranges (e.g., office egress IPs, VPN ranges) and deny everything else.

```bash
az network application-gateway waf-policy custom-rule create \
  --resource-group "rg-cwm-reporting" \
  --policy-name "cwm-waf-policy" \
  --name "AllowCorporateIPs" \
  --priority 10 \
  --rule-type MatchRule \
  --action Allow

az network application-gateway waf-policy custom-rule match-condition add \
  --resource-group "rg-cwm-reporting" \
  --policy-name "cwm-waf-policy" \
  --name "AllowCorporateIPs" \
  --match-variables RemoteAddr \
  --operator IPMatch \
  --values "203.0.113.0/24" "198.51.100.0/24"
```

> Replace `203.0.113.0/24` and `198.51.100.0/24` with your organization's actual public IP ranges. Add as many CIDR blocks as needed.

Then add a lower-priority rule to deny all other traffic:

```bash
az network application-gateway waf-policy custom-rule create \
  --resource-group "rg-cwm-reporting" \
  --policy-name "cwm-waf-policy" \
  --name "DenyAll" \
  --priority 100 \
  --rule-type MatchRule \
  --action Block

az network application-gateway waf-policy custom-rule match-condition add \
  --resource-group "rg-cwm-reporting" \
  --policy-name "cwm-waf-policy" \
  --name "DenyAll" \
  --match-variables RemoteAddr \
  --operator IPMatch \
  --negate true \
  --values "127.0.0.1"
```

> This rule matches all remote addresses (by negating a match against `127.0.0.1`) and blocks them. Because the `AllowCorporateIPs` rule has a higher priority (lower number), allowed IPs are evaluated first and pass through.

### 7.2 Apply an NSG to the Application Gateway Subnet (Optional)

For defense in depth, add a Network Security Group to the Application Gateway subnet to restrict inbound traffic at the network layer:

```bash
az network nsg create \
  --resource-group "rg-cwm-reporting" \
  --name "cwm-appgw-nsg" \
  --location "eastus"

# Allow HTTP from corporate IP ranges
az network nsg rule create \
  --resource-group "rg-cwm-reporting" \
  --nsg-name "cwm-appgw-nsg" \
  --name "AllowHTTPFromCorp" \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --destination-port-ranges 80 443 \
  --source-address-prefixes "203.0.113.0/24" "198.51.100.0/24"

# Required: Allow Application Gateway infrastructure traffic
az network nsg rule create \
  --resource-group "rg-cwm-reporting" \
  --nsg-name "cwm-appgw-nsg" \
  --name "AllowGatewayManager" \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --destination-port-ranges 65200-65535 \
  --source-address-prefixes GatewayManager

# Deny all other inbound traffic
az network nsg rule create \
  --resource-group "rg-cwm-reporting" \
  --nsg-name "cwm-appgw-nsg" \
  --name "DenyAllInbound" \
  --priority 4096 \
  --direction Inbound \
  --access Deny \
  --protocol "*" \
  --destination-port-ranges "*" \
  --source-address-prefixes "*"

# Associate NSG with the Application Gateway subnet
az network vnet subnet update \
  --resource-group "rg-cwm-reporting" \
  --vnet-name "cwm-vnet" \
  --name "appgw-subnet" \
  --network-security-group "cwm-appgw-nsg"
```

> Replace the source address prefixes with your organization's actual public IP ranges. The `GatewayManager` rule on ports 65200–65535 is **required** for Application Gateway v2 health probes and must not be removed.

### 7.3 Enable HTTPS with a TLS Certificate (Optional but Recommended)

To serve the dashboard over HTTPS, add your TLS certificate and an HTTPS listener to the Application Gateway.

1. Upload your PFX certificate:

```bash
az network application-gateway ssl-cert create \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "cwm-tls-cert" \
  --cert-file "./certificate.pfx" \
  --cert-password "<pfx-password>"
```

2. Add an HTTPS frontend port and listener:

```bash
az network application-gateway frontend-port create \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "httpsPort" \
  --port 443

az network application-gateway http-listener create \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "httpsListener" \
  --frontend-port "httpsPort" \
  --frontend-ip "appGatewayFrontendIP" \
  --ssl-cert "cwm-tls-cert"

az network application-gateway rule create \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "httpsRule" \
  --priority 100 \
  --http-listener "httpsListener" \
  --address-pool "appGatewayBackendPool" \
  --http-settings "appGatewayBackendHttpSettings"
```

3. Optionally add a redirect rule to send HTTP traffic to HTTPS:

```bash
az network application-gateway redirect-config create \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "httpToHttpsRedirect" \
  --type Permanent \
  --target-listener "httpsListener"

az network application-gateway rule update \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "rule1" \
  --redirect-config "httpToHttpsRedirect"
```

### 7.4 Configure Health Probes

Create a custom health probe so the Application Gateway can verify the web container is responding:

```bash
az network application-gateway probe create \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "cwm-health-probe" \
  --protocol Http \
  --host-name-from-http-settings true \
  --path "/" \
  --interval 30 \
  --timeout 30 \
  --threshold 3

az network application-gateway http-settings update \
  --resource-group "rg-cwm-reporting" \
  --gateway-name "cwm-appgw" \
  --name "appGatewayBackendHttpSettings" \
  --probe "cwm-health-probe"
```

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

### 9.2 Update the Application Gateway Backend After Deployment

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

### 9.3 DNS Zone Name in Workflow (If Applicable)

If the workflow still references a `DNS_ZONE_NAME` variable (e.g., for a non-static-IP setup), it can be removed. DNS is now managed directly in your organization's existing authoritative zone (see [Part 5](#part-5--dns-configuration-510-min)) and does not require updates during deployment.

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

1. Navigate to your hostname (e.g., `http://reports.mycompany.com` or `https://reports.mycompany.com` if TLS was configured in [Part 7.3](#73-enable-https-with-a-tls-certificate-optional-but-recommended)).
2. If WAF IP restrictions are configured ([Part 7.1](#71-restrict-access-by-source-ip-recommended)), verify that access works from an allowed IP and is blocked from a non-allowed IP.
3. The CWM Custom Reporting dashboard should load.
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
| 4 | Static Public IP and Application Gateway | 15–25 min |
| 5 | DNS Configuration | 5–10 min |
| 6 | Service Principal | 10–15 min |
| 7 | Application Gateway WAF and Access Protection | 15–25 min |
| 8 | GitHub Repository and Secrets | 15–20 min |
| 9 | Workflow Modifications | 10–15 min |
| 10 | Deployment and Validation | 15–20 min |
| | **Total** | **~2–3 hours** |

> DNS propagation ([Part 5.3](#53-verify-dns-resolution)) timing depends on your DNS provider and TTL settings. It typically resolves within minutes.

---

## Ongoing Maintenance

- **ACR credentials** — Rotate the ACR admin password periodically and update the `ACR_PASSWORD` GitHub secret.
- **Service principal secret** — The client secret expires after one year by default. Set a calendar reminder to rotate it and update `AZURE_CREDENTIALS` in GitHub.
- **Storage account keys** — Rotate keys periodically and update `AZURE_STORAGE_ACCOUNT_KEY` in GitHub after rotation.
- **CWM API keys** — If ConnectWise keys are rotated, update all `CWM_*` secrets in GitHub.
- **Application Gateway** — Monitor the gateway's health through Azure Monitor. Review WAF logs periodically to detect blocked threats and adjust custom rules as needed.
- **WAF IP allow list** — When corporate IP ranges change (e.g., office moves, new VPN egress IPs), update the WAF custom rules in [Part 7.1](#71-restrict-access-by-source-ip-recommended) and the NSG rules in [Part 7.2](#72-apply-an-nsg-to-the-application-gateway-subnet-optional) to maintain access.
- **TLS certificates** — If HTTPS was configured on the Application Gateway ([Part 7.3](#73-enable-https-with-a-tls-certificate-optional-but-recommended)), track certificate expiration and renew before it expires.
- **DNS records** — If the static public IP ever changes (unlikely unless the IP resource is deleted and recreated), update the A record in your authoritative DNS zone.
