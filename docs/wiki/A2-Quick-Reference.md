# Quick Reference Card

A single-page reference for the most commonly needed resources, commands, and procedures.

---

## Azure Resources

| Resource | Name / Value |
|----------|--------------|
| Subscription ID | `<your-subscription-id>` |
| Tenant ID | `<your-tenant-id>` |
| ACR | `<your-acr-name>` |
| ACR Login Server | `<your-acr-name>.azurecr.io` |
| IoT Hub | `<your-iothub-name>` |
| Log Analytics Workspace | `<your-workspace-name>` |
| Log Analytics Workspace ID | `<your-workspace-id>` |
| Arc Cluster | `aks-edge-ipc-factory-01` |
| Arc Resource Group | `rg-ipc-platform-arc` |
| Storage Account | `stipcplatformXXXX` |

---

## Resource Groups

| Resource Group | Purpose |
|----------------|---------|
| `rg-ipc-platform-images` | Packer golden images |
| `rg-ipc-platform-arc` | Arc-connected resources |
| `rg-ipc-platform-monitoring` | Log Analytics, dashboards |
| `rg-ipc-platform-acr` | Container registry |

---

## Local Paths (workstation)

| Item | Path |
|------|------|
| Git Repository | `C:\Projects\IPC-Platform-Engineering` |
| Packer Source | `C:\Projects\IPC-Platform-Engineering\packer` |
| Packer Output | `E:\IPC-Build\output-ipc-golden` |
| VM Storage | `E:\Factory-VMs` |
| Windows ISO | `F:\ISOs\en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso` |

---

## URLs

| Resource | URL |
|----------|-----|
| Azure Portal | https://portal.azure.com |
| Azure DevOps | https://dev.azure.com/<your-org>/IPC-Platform-Engineering |
| ACR Portal | https://portal.azure.com/#@/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-ipc-platform-acr/providers/Microsoft.ContainerRegistry/registries/<your-acr-name> |
| Arc Cluster | https://portal.azure.com/#@/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-ipc-platform-arc/providers/Microsoft.Kubernetes/connectedClusters/aks-edge-ipc-factory-01 |

---

## Essential kubectl Commands

```powershell
# Cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# All workloads status
kubectl get pods -n ipc-workloads
kubectl get deployments -n ipc-workloads
kubectl get services -n ipc-workloads

# Production workloads only
kubectl get pods -n ipc-workloads -l workload-type=production

# Simulators only
kubectl get pods -n ipc-workloads -l workload-type=simulator

# View logs
kubectl logs deployment/<workload> -n ipc-workloads
kubectl logs deployment/<workload> -n ipc-workloads --tail=50
kubectl logs deployment/<workload> -n ipc-workloads -f  # Follow

# Describe (for troubleshooting)
kubectl describe pod <pod-name> -n ipc-workloads
kubectl describe deployment <n> -n ipc-workloads

# Restart deployment
kubectl rollout restart deployment/<n> -n ipc-workloads

# Delete pods (forces recreation)
kubectl delete pods -n ipc-workloads -l app=<n>

# Exec into container
kubectl exec -it deployment/<n> -n ipc-workloads -- /bin/sh

# Recent events
kubectl get events -n ipc-workloads --sort-by='.lastTimestamp' | tail -20
```

---

## GitOps Commands

```powershell
# Check GitOps status
kubectl get gitrepositories -n flux-system
kubectl get kustomizations -n flux-system

# Force immediate sync
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# View Flux logs
kubectl logs -n flux-system deployment/source-controller
kubectl logs -n flux-system deployment/kustomize-controller
```

---

## Azure CLI Commands

```powershell
# Build container image
az acr build --registry <your-acr-name> `
  --image ipc/<workload>:latest `
  --file docker/<workload>/Dockerfile `
  docker/<workload>/

# Check Arc connection
az connectedk8s show `
  --name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --query "connectivityStatus"

# Monitor IoT Hub messages (all)
az iot hub monitor-events `
  --hub-name "<your-iothub-name>" `
  --properties all

# Monitor IoT Hub messages (specific device)
az iot hub monitor-events `
  --hub-name "<your-iothub-name>" `
  --device-id "ipc-factory-01"

# List ACR images
az acr repository list --name <your-acr-name> --output table
az acr repository show-tags --name <your-acr-name> --repository ipc/<workload>
```

---

## Git Workflow

```powershell
cd C:\Projects\IPC-Platform-Engineering

# Create feature branch
git checkout -b feature/<n>

# Stage and commit
git add .
git commit -m "feat(<scope>): description"

# Push
git push origin feature/<n>

# After PR merged, update local main
git checkout main
git pull origin main
```

---

## Packer Commands

```powershell
cd C:\Projects\IPC-Platform-Engineering\packer

# Initialize plugins (first time only)
packer init ipc-golden.pkr.hcl

# Validate template
packer validate ipc-golden.pkr.hcl

# Build golden image
packer build ipc-golden.pkr.hcl

# Output location: E:\IPC-Build\output-ipc-golden\
```

---

## Credential Retrieval

```powershell
# Log Analytics Workspace Key
az monitor log-analytics workspace get-shared-keys `
  --resource-group rg-ipc-platform-monitoring `
  --workspace-name <your-workspace-name> `
  --query primarySharedKey -o tsv

# ACR Admin Password
az acr credential show --name <your-acr-name> `
  --query "passwords[0].value" -o tsv

# IoT Hub Device Connection String
az iot hub device-identity connection-string show `
  --hub-name <your-iothub-name> `
  --device-id ipc-factory-01 `
  --query connectionString -o tsv

# Blob Storage Connection String
az storage account show-connection-string `
  --name <storage-account-name> `
  --resource-group rg-ipc-platform-monitoring `
  --query connectionString -o tsv
```

---

## Startup Sequence

```powershell
# 1. On workstation - Start the VM
Start-VM -Name "IPC-Factory-01"

# 2. Wait 2 minutes for Windows to boot

# 3. On VM - Start AKS Edge (if not auto-starting)
Import-Module AksEdge
Start-AksEdgeNode -NodeType Linux

# 4. Wait 60 seconds

# 5. Verify
kubectl get nodes          # Should show Ready
kubectl get pods -A        # All should be Running
```

---

## Shutdown Sequence

```powershell
# 1. On VM - Stop AKS Edge gracefully
Import-Module AksEdge
Stop-AksEdgeNode -NodeType Linux

# 2. Wait for completion

# 3. On workstation - Stop the VM
Stop-VM -Name "IPC-Factory-01"
```

**Important:** Always stop the Linux node gracefully to avoid Calico CNI issues on next startup.

---

## Workload Names

### Production Workloads (Ship to Customers)

| Workload | Deployment Name | Service Name | Port |
|----------|-----------------|--------------|------|
| OPC-UA Gateway | `opcua-gateway` | — | — |
| Health Monitor | `health-monitor` | — | — |
| Log Forwarder | `log-forwarder` | — | — |
| Anomaly Detection | `anomaly-detection` | — | — |
| Test Data Collector | `test-data-collector` | — | — |

### PoC Simulators (Demo Only)

| Simulator | Deployment Name | Service Name | Port |
|-----------|-----------------|--------------|------|
| OPC-UA Simulator | `opcua-simulator` | `opcua-simulator` | 4840 |
| EV Battery Simulator | `ev-battery-simulator` | — | — |
| Vision Simulator | `vision-simulator` | — | — |
| Motion Simulator | `motion-simulator` | `motion-simulator` | 4841 |
| Motion Gateway | `motion-gateway` | — | — |

**Total Running Pods:** 10 (5 production + 5 simulators)

---

## Secrets

| Secret Name | Namespace | Contents |
|-------------|-----------|----------|
| `acr-pull-secret` | `ipc-workloads` | ACR credentials for image pull |
| `azure-monitor-credentials` | `ipc-workloads` | Log Analytics workspaceId, workspaceKey |
| `iot-hub-connection` | `ipc-workloads` | IoT Hub connectionString |
| `blob-storage-credentials` | `ipc-workloads` | Blob Storage connectionString |

---

## Log Analytics Tables

| Table | Source | Contents |
|-------|--------|----------|
| `IPCHealthMonitor_CL` | health-monitor | CPU, memory, disk metrics |
| `IPCSecurityAudit_CL` | log-forwarder | Security event logs |

---

## Common KQL Queries

```kql
// Recent health data
IPCHealthMonitor_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, deviceId_s, system_cpu_percent_d, system_memory_percent_d
| order by TimeGenerated desc

// Security events summary
IPCSecurityAudit_CL
| where TimeGenerated > ago(24h)
| summarize count() by EventType_s

// Failed logons
IPCSecurityAudit_CL
| where TimeGenerated > ago(24h)
| where EventID_d == 4625
| project TimeGenerated, Computer_s, Account_s
```

---

## Simulator Log Commands

Quick commands for checking each simulator's output:

```powershell
# OPC-UA Simulator (generic PLC)
kubectl logs deployment/opcua-simulator -n ipc-workloads --tail=10

# EV Battery Simulator (high-speed 96-cell data)
kubectl logs deployment/ev-battery-simulator -n ipc-workloads --tail=10

# Vision Simulator (PASS/FAIL inspection events)
kubectl logs deployment/vision-simulator -n ipc-workloads --tail=10

# Motion Simulator (OPC-UA gantry server)
kubectl logs deployment/motion-simulator -n ipc-workloads --tail=10

# Motion Gateway (gantry data to IoT Hub)
kubectl logs deployment/motion-gateway -n ipc-workloads --tail=10
```

---

## Required Azure Endpoints (for Customer Firewall)

| Service | Endpoint | Port |
|---------|----------|------|
| Azure Arc | *.guestconfiguration.azure.com | 443 |
| Azure Arc | *.his.arc.azure.com | 443 |
| Azure Arc | *.kubernetesconfiguration.azure.com | 443 |
| Log Analytics | *.ods.opinsights.azure.com | 443 |
| Log Analytics | *.oms.opinsights.azure.com | 443 |
| IoT Hub | *.azure-devices.net | 443 |
| ACR | *.azurecr.io | 443 |
| Azure Management | management.azure.com | 443 |

---

## Emergency Recovery

### If Cluster Is Completely Unresponsive

```powershell
# On VM
Import-Module AksEdge
Stop-AksEdgeNode -NodeType Linux
Start-Sleep -Seconds 30
Start-AksEdgeNode -NodeType Linux
Start-Sleep -Seconds 90
kubectl get nodes
```

### If GitOps Won't Sync

```powershell
# Force sync
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# If still failing, check Flux logs
kubectl logs -n flux-system deployment/source-controller
```

### If Pod Won't Start

```powershell
# Get details
kubectl describe pod <pod-name> -n ipc-workloads

# Check for common issues:
# - ErrImagePull → verify acr-pull-secret
# - CrashLoopBackOff → check logs with --previous flag
# - Pending → check resource constraints
```

### If Simulator Not Producing Data

```powershell
# Check if IoT Hub connection is configured
kubectl get secret iot-hub-connection -n ipc-workloads

# Restart specific simulator
kubectl rollout restart deployment/ev-battery-simulator -n ipc-workloads

# Check IoT Hub is receiving messages
az iot hub monitor-events --hub-name "<your-iothub-name>" --properties all
```

---

## Utility Scripts

All scripts are in `scripts/` and use PowerShell convention (`Verb-Noun.ps1`).

### Bootstrap-Secrets.ps1

**Purpose:** Creates required Kubernetes secrets for IPC Platform workloads by auto-discovering Azure resources.

**Location:** `scripts/Bootstrap-Secrets.ps1`

**Usage:**
```powershell
# Basic usage (auto-discovers resources)
.\scripts\Bootstrap-Secrets.ps1

# Specify ACR name explicitly
.\scripts\Bootstrap-Secrets.ps1 -AcrName "<your-acr-name>"

# Force overwrite existing secrets
.\scripts\Bootstrap-Secrets.ps1 -Force
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `-AcrName` | No | Azure Container Registry name (default: <your-acr-name>) |
| `-Force` | No | Overwrite existing secrets |

**Prerequisites:**
- Azure CLI authenticated (`az login`)
- kubectl configured for target cluster
- Appropriate RBAC permissions for ACR, Log Analytics, IoT Hub

**Secrets Created:**
| Secret | Keys | Source |
|--------|------|--------|
| `acr-pull-secret` | (docker-registry) | ACR admin credentials |
| `log-analytics-connection` | workspaceId, key | Auto-discovered workspace |
| `iot-hub-connection` | connectionString | Auto-discovered IoT Hub |

---

### New-Workload.ps1

**Purpose:** Scaffolds a complete new workload with Dockerfile, Kubernetes manifests, pipeline, and Flux image automation.

**Location:** `scripts/New-Workload.ps1`

**Usage:**
```powershell
# Create a new workload named "my-service"
.\scripts\New-Workload.ps1 -Name "my-service"
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `-Name` | Yes | Workload name (lowercase, hyphenated) |

**Files Created:**
```
docker/my-service/
├── Dockerfile
├── azure-pipelines.yml
├── .trivyignore
└── src/
    └── main.py

kubernetes/workloads/my-service/
├── deployment.yaml
└── kustomization.yaml

# Also appends to:
# - kubernetes/flux-system/image-automation/image-repositories.yaml
# - kubernetes/flux-system/image-automation/image-policies.yaml
```

**Next Steps After Running:**
1. Customize `docker/<name>/src/main.py` with your logic
2. Update `docker/<name>/requirements.txt` with dependencies
3. Commit and push to trigger the build pipeline
4. Register pipeline in Azure DevOps

---

### Other Utility Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `Check-Builds.ps1` | Verify all workload builds completed successfully | `.\scripts\Check-Builds.ps1` |
| `Trigger-Pipelines.ps1` | Trigger all workload build pipelines | `.\scripts\Trigger-Pipelines.ps1` |
| `Create-Pipelines.ps1` | Register azure-pipelines.yml files in Azure DevOps | `.\scripts\Create-Pipelines.ps1` |
| `Apply-Security-Fix.ps1` | Apply security fixes across all Dockerfiles | `.\scripts\Apply-Security-Fix.ps1` |
| `Apply-Trivy-Ignore.ps1` | Add CVE to all workload .trivyignore files | `.\scripts\Apply-Trivy-Ignore.ps1 -CVE "CVE-2024-xxxx"` |
| `Restrict-Triggers.ps1` | Restrict pipeline triggers to main branch only | `.\scripts\Restrict-Triggers.ps1` |

---

## Flux Sync Commands

```powershell
# Check sync status
kubectl get gitrepositories -n flux-system
kubectl get kustomizations -n flux-system

# Force immediate sync
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# Check Image Automation
kubectl get imagerepositories -n flux-system
kubectl get imagepolicies -n flux-system

# Force image scan
kubectl annotate imagerepository health-monitor -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

---

## Related Pages

- [Troubleshooting](A1-Troubleshooting.md) — Detailed issue resolution
- [Demo Script](11-Demo-Script.md) — Pre-demo checklists
- [Edge Deployment](03-Edge-Deployment.md) — AKS Edge details
- [GitOps Configuration](04-GitOps-Configuration.md) — Flux setup, Image Automation
- [OPC-UA Workloads](05-Workloads-OPC-UA.md) — Simulator documentation

