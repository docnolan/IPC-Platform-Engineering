# Azure Foundation
# Infrastructure and Resource Configuration

---

# Table of Contents

1. [Subscription and Identity](#1-subscription-and-identity)
2. [Resource Groups](#2-resource-groups)
3. [Resource Provider Registrations](#3-resource-provider-registrations)
4. [Deployed Resources](#4-deployed-resources)
5. [Azure DevOps Configuration](#5-azure-devops-configuration)
6. [Network Requirements](#6-network-requirements)
7. [Azure Free Tier Adequacy](#7-azure-free-tier-adequacy)
8. [Credentials Reference](#8-credentials-reference)

---

# 1. Subscription and Identity

| Property | Value |
|----------|-------|
| Subscription Name | Azure subscription 1 |
| Subscription ID | `<your-subscription-id>` |
| Tenant ID | `<your-tenant-id>` |
| Authentication | Workload Identity Federation (no stored secrets) |

## 1.1 Workload Identity Federation

The Azure DevOps service connection uses Workload Identity Federation rather than a service principal secret. This means:

- No credentials stored in Azure DevOps
- No secret rotation required
- Audit trail of all Azure operations
- Aligns with NIST 800-171 3.5.1 (Identify users) and 3.5.2 (Authenticate devices)

**Service Connection Name:** `azure-subscription`

## 1.2 Required Permissions

| Resource | Required Role | Purpose |
|----------|---------------|---------|
| Azure Subscription | Owner or Contributor | Resource deployment |
| Microsoft Entra ID | Application Administrator | Service principal creation |
| Azure DevOps | Project Collection Administrator | Pipeline configuration |

---

# 2. Resource Groups

| Resource Group | Location | Purpose |
|----------------|----------|---------|
| `rg-ipc-platform-images` | Central US | Packer golden images (future Azure builds) |
| `rg-ipc-platform-arc` | Central US | Arc-connected resources |
| `rg-ipc-platform-monitoring` | Central US | Log Analytics, IoT Hub, Blob Storage |
| `rg-ipc-platform-acr` | Central US | Container Registry |

## 2.1 Creation Commands (Reference)

```powershell
# These were run during initial setup
az group create --name "rg-ipc-platform-images" --location "centralus"
az group create --name "rg-ipc-platform-arc" --location "centralus"
az group create --name "rg-ipc-platform-monitoring" --location "centralus"
az group create --name "rg-ipc-platform-acr" --location "centralus"
```

---

# 3. Resource Provider Registrations

The following providers were registered to enable Azure services:

| Provider | Purpose | Status |
|----------|---------|--------|
| Microsoft.Kubernetes | Arc-enabled Kubernetes | Registered |
| Microsoft.KubernetesConfiguration | GitOps/Flux | Registered |
| Microsoft.ExtendedLocation | Custom locations | Registered |
| Microsoft.HybridCompute | Arc-enabled servers | Registered |
| Microsoft.ContainerRegistry | ACR | Registered |
| Microsoft.Devices | IoT Hub | Registered |
| Microsoft.OperationalInsights | Log Analytics | Registered |

## 3.1 Registration Commands (Reference)

```powershell
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation
az provider register --namespace Microsoft.HybridCompute
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Devices
az provider register --namespace Microsoft.OperationalInsights

# Verify registration
az provider show --namespace Microsoft.Kubernetes --query "registrationState" -o tsv
```

---

# 4. Deployed Resources

## 4.1 Azure Container Registry

| Property | Value |
|----------|-------|
| Name | `<your-acr-name>` |
| Login Server | `<your-acr-name>.azurecr.io` |
| SKU | Basic |
| Resource Group | rg-ipc-platform-acr |
| Admin Enabled | Yes (for PoC; disable in production) |

**Creation Command (Reference):**
```powershell
az acr create `
  --resource-group "rg-ipc-platform-acr" `
  --name "<your-acr-name>" `
  --sku Basic `
  --admin-enabled true
```

**Retrieve Admin Password:**
```powershell
az acr credential show --name <your-acr-name> --query "passwords[0].value" -o tsv
```

**List Images:**
```powershell
az acr repository list --name <your-acr-name> --output table
```

---

## 4.2 Azure IoT Hub

| Property | Value |
|----------|-------|
| Name | `<your-iothub-name>` |
| Hostname | `<your-iothub-name>.azure-devices.net` |
| SKU | F1 (Free) |
| Resource Group | rg-ipc-platform-monitoring |
| Registered Device | `ipc-factory-01` |

**Creation Command (Reference):**
```powershell
az iot hub create `
  --resource-group "rg-ipc-platform-monitoring" `
  --name "<your-iothub-name>" `
  --sku F1 `
  --partition-count 2
```

**Register Device:**
```powershell
az iot hub device-identity create `
  --hub-name "<your-iothub-name>" `
  --device-id "ipc-factory-01" `
  --edge-enabled false
```

**Retrieve Device Connection String:**
```powershell
az iot hub device-identity connection-string show `
  --hub-name "<your-iothub-name>" `
  --device-id "ipc-factory-01" `
  --query connectionString -o tsv
```

**Monitor Device Telemetry:**
```powershell
# Requires az iot extension
az iot hub monitor-events --hub-name "<your-iothub-name>" --device-id "ipc-factory-01"
```

---

## 4.3 Log Analytics Workspace

| Property | Value |
|----------|-------|
| Name | `<your-workspace-name>` |
| Workspace ID | `<your-workspace-id>` |
| Resource Group | rg-ipc-platform-monitoring |
| Retention | 90 days (CMMC requirement) |

**Creation Command (Reference):**
```powershell
az monitor log-analytics workspace create `
  --resource-group "rg-ipc-platform-monitoring" `
  --workspace-name "<your-workspace-name>" `
  --location "centralus" `
  --retention-time 90
```

**Retrieve Workspace Key:**
```powershell
az monitor log-analytics workspace get-shared-keys `
  --resource-group "rg-ipc-platform-monitoring" `
  --workspace-name "<your-workspace-name>" `
  --query primarySharedKey -o tsv
```

**Query Logs (via Azure CLI):**
```powershell
az monitor log-analytics query `
  --workspace "<your-workspace-id>" `
  --analytics-query "IPCComplianceLogs_CL | take 10"
```

---

## 4.4 Azure Blob Storage

| Property | Value |
|----------|-------|
| Account Name | `stipcplatformXXXX` (your unique name) |
| Container | `test-results` |
| SKU | Standard_LRS |
| Resource Group | rg-ipc-platform-monitoring |

**Creation Command (Reference):**
```powershell
$STORAGE_NAME = "stipcplatform$(Get-Random -Maximum 9999)"

az storage account create `
  --name $STORAGE_NAME `
  --resource-group "rg-ipc-platform-monitoring" `
  --location "centralus" `
  --sku Standard_LRS

az storage container create `
  --name "test-results" `
  --account-name $STORAGE_NAME
```

**Retrieve Connection String:**
```powershell
az storage account show-connection-string `
  --name $STORAGE_NAME `
  --resource-group "rg-ipc-platform-monitoring" `
  --query connectionString -o tsv
```

---

## 4.5 Arc-Connected Cluster

| Property | Value |
|----------|-------|
| Name | `aks-edge-ipc-factory-01` |
| Resource Group | rg-ipc-platform-arc |
| Distribution | AKS Edge Essentials (K3s) |
| Connected From | IPC-Factory-01 VM |
| GitOps Extension | microsoft.flux |

**View in Azure Portal:**
```
Azure Portal → Kubernetes - Azure Arc → aks-edge-ipc-factory-01
```

**Check Connection Status:**
```powershell
az connectedk8s show `
  --name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --query "connectivityStatus"
```

---

# 5. Azure DevOps Configuration

| Property | Value |
|----------|-------|
| Organization URL | `https://dev.azure.com/<your-org>` |
| Project Name | `IPC-Platform-Engineering` |
| Repository | `IPC-Platform-Engineering` |
| Service Connection | `azure-subscription` (Workload Identity Federation) |

## 5.1 Variable Group

**Name:** `ipc-platform-variables`

| Variable | Value | Secret? |
|----------|-------|---------|
| azureSubscriptionId | `<your-subscription-id>` | No |
| azureTenantId | `<your-tenant-id>` | No |
| location | `centralus` | No |
| acrName | `<your-acr-name>` | No |
| iotHubName | `<your-iothub-name>` | No |
| logAnalyticsWorkspaceId | `<your-workspace-id>` | No |
| arcClusterName | `aks-edge-ipc-factory-01` | No |
| arcResourceGroup | `rg-ipc-platform-arc` | No |

## 5.2 Create Variable Group via CLI

```powershell
# Install Azure DevOps extension if not present
az extension add --name azure-devops

# Configure defaults
az devops configure --defaults organization=https://dev.azure.com/<your-org> project=IPC-Platform-Engineering

# Create variable group
az pipelines variable-group create `
  --name "ipc-platform-variables" `
  --variables `
    azureSubscriptionId="<your-subscription-id>" `
    azureTenantId="<your-tenant-id>" `
    location="centralus" `
    acrName="<your-acr-name>" `
    iotHubName="<your-iothub-name>" `
    logAnalyticsWorkspaceId="<your-workspace-id>" `
    arcClusterName="aks-edge-ipc-factory-01" `
    arcResourceGroup="rg-ipc-platform-arc"
```

---

# 6. Network Requirements

## 6.1 Critical Design Principle

**All connections are OUTBOUND from the IPC.**

No inbound firewall rules are required at customer sites. The Arc agent and IoT Hub clients initiate outbound HTTPS connections to Azure endpoints.

```
IPC (Inside Customer Firewall)
    │
    ├──► Azure Arc Endpoints (HTTPS 443)
    │    ├── *.guestconfiguration.azure.com
    │    ├── *.his.arc.azure.com
    │    ├── *.dp.kubernetesconfiguration.azure.com
    │    └── management.azure.com
    │
    ├──► Azure IoT Hub (MQTT 8883 or AMQP 5671)
    │    └── <your-iothub-name>.azure-devices.net
    │
    ├──► Azure Container Registry (HTTPS 443)
    │    └── <your-acr-name>.azurecr.io
    │
    └──► Azure Monitor (HTTPS 443)
         └── *.ods.opinsights.azure.com
```

## 6.2 Full Azure Arc Endpoint List

The following endpoints must be accessible (outbound HTTPS 443) for Azure Arc connectivity:

| Endpoint | Purpose |
|----------|---------|
| `management.azure.com` | Azure Resource Manager |
| `login.microsoftonline.com` | Microsoft Entra ID authentication |
| `*.login.microsoftonline.com` | Microsoft Entra ID authentication |
| `mcr.microsoft.com` | Microsoft Container Registry |
| `*.data.mcr.microsoft.com` | Microsoft Container Registry content |
| `gbl.his.arc.azure.com` | Arc service metadata |
| `*.his.arc.azure.com` | Arc service regional endpoint |
| `*.guestconfiguration.azure.com` | Guest configuration (compliance) |
| `*.dp.kubernetesconfiguration.azure.com` | Kubernetes configuration |
| `dc.services.visualstudio.com` | Application Insights telemetry |
| `*.ods.opinsights.azure.com` | Log Analytics data ingestion |
| `*.oms.opinsights.azure.com` | Log Analytics OMS |

## 6.3 Connectivity Test Script

```powershell
# Test-AzureConnectivity.ps1
# Run on IPC to verify outbound connectivity

$endpoints = @(
    "management.azure.com",
    "login.microsoftonline.com",
    "mcr.microsoft.com",
    "gbl.his.arc.azure.com",
    "centralus.his.arc.azure.com",
    "<your-acr-name>.azurecr.io",
    "<your-iothub-name>.azure-devices.net"
)

foreach ($endpoint in $endpoints) {
    $result = Test-NetConnection -ComputerName $endpoint -Port 443
    if ($result.TcpTestSucceeded) {
        Write-Host " $endpoint - Connected" -ForegroundColor Green
    } else {
        Write-Host " $endpoint - FAILED" -ForegroundColor Red
    }
}
```

---

# 7. Azure Free Tier Adequacy

| Service | Free Tier Limit | PoC Usage | Sufficient? |
|---------|-----------------|-----------|-------------|
| Azure Arc (Servers) | Free | 1 server | Yes |
| Azure Arc (Kubernetes) | Free | 1 cluster | Yes |
| Log Analytics | 5 GB/month free | ~100 MB/month | Yes |
| Azure IoT Hub | 8,000 msgs/day (F1) | ~1,000 msgs/day | Yes |
| Container Registry | Basic tier (~$5/month) | Required for images | Minimal cost |
| Blob Storage | First 5 GB free | ~1 GB | Yes |

**Estimated Monthly Cost:** $5-10 (primarily ACR Basic tier)

---

# 8. Credentials Reference

**Store these securely. Never commit to Git.**

| Credential | Storage Location | Retrieval Method |
|------------|------------------|------------------|
| Log Analytics Workspace Key | Local secure storage | `az monitor log-analytics workspace get-shared-keys ...` |
| ACR Admin Password | Local secure storage | `az acr credential show ...` |
| IoT Hub Device Connection String | Local secure storage | `az iot hub device-identity connection-string show ...` |
| Blob Storage Connection String | Local secure storage | `az storage account show-connection-string ...` |
| Azure DevOps PAT | Local secure storage | Azure DevOps → Profile → Personal access tokens |

## 8.1 Credential Retrieval Commands

```powershell
# ACR Admin Password
az acr credential show --name <your-acr-name> --query "passwords[0].value" -o tsv

# Log Analytics Workspace Key
az monitor log-analytics workspace get-shared-keys `
  --resource-group "rg-ipc-platform-monitoring" `
  --workspace-name "<your-workspace-name>" `
  --query primarySharedKey -o tsv

# IoT Hub Device Connection String
az iot hub device-identity connection-string show `
  --hub-name "<your-iothub-name>" `
  --device-id "ipc-factory-01" `
  --query connectionString -o tsv

# Blob Storage Connection String
az storage account show-connection-string `
  --name "stipcplatformXXXX" `
  --resource-group "rg-ipc-platform-monitoring" `
  --query connectionString -o tsv
```

## 8.2 Security Best Practices

| Practice | PoC Status | Production Recommendation |
|----------|------------|---------------------------|
| ACR Admin Account | Enabled | Disable; use managed identity |
| Service Principal Secrets | Not used (WIF) | Continue using WIF |
| Connection Strings | In K8s secrets | Use Azure Key Vault |
| PAT for GitOps | Used | Switch to managed identity |
| Local Credential Storage | Secure file | Azure Key Vault + managed identity |

---

*End of Azure Foundation Section*

**Previous:** [00-Overview.md](00-Overview.md)  
**Next:** [02-Golden-Image-Pipeline.md](02-Golden-Image-Pipeline.md)
