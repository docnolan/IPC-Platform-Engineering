# Edge Deployment
# AKS Edge Essentials and Azure Arc Configuration

---

# Table of Contents

1. [Overview](#1-overview)
2. [Development Environment](#2-development-environment)
3. [AKS Edge Essentials](#3-aks-edge-essentials)
4. [Azure Arc Connection](#4-azure-arc-connection)
5. [Kubernetes Namespaces](#5-kubernetes-namespaces)
6. [ACR Pull Secret](#6-acr-pull-secret)
7. [Operational Procedures](#7-operational-procedures)

---

# 1. Overview

The edge deployment consists of three layers:

| Layer | Component | Purpose |
|-------|-----------|---------|
| 1 | Windows 10 IoT Enterprise | Host OS from golden image |
| 2 | AKS Edge Essentials (K3s) | Lightweight Kubernetes runtime |
| 3 | Azure Arc | Cloud management plane connectivity |

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           EDGE DEPLOYMENT STACK                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │  Layer 3: Azure Arc                                                       │ │
│  │  • Cloud management plane connectivity                                    │ │
│  │  • GitOps (Flux) for configuration management                            │ │
│  │  • Centralized monitoring and policy                                     │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                     ▲                                           │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │  Layer 2: AKS Edge Essentials (K3s)                                       │ │
│  │  • Lightweight Kubernetes runtime                                        │ │
│  │  • Container orchestration                                               │ │
│  │  • Runs in CBL-Mariner Linux VM                                         │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                     ▲                                           │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │  Layer 1: Windows 10 IoT Enterprise LTSC                                  │ │
│  │  • Host operating system                                                 │ │
│  │  • CIS Benchmark hardened                                                │ │
│  │  • Hyper-V hypervisor for K3s VM                                        │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

# 2. Development Environment

## 2.1 Host Machine (workstation)

| Property | Value |
|----------|-------|
| Model | development workstation |
| CPU | Intel Xeon E3-1505M (4 cores, 8 threads) |
| Hypervisor | Hyper-V |
| VM Storage | `E:\Factory-VMs\` |

## 2.2 Demo VM (IPC-Factory-01)

| Property | Value |
|----------|-------|
| VM Name | `IPC-Factory-01` |
| vCPUs | 4 |
| RAM | 8 GB |
| Disk | `E:\Factory-VMs\Factory-VMs\IPC-Factory-01.vhdx` |
| OS | Windows 10 IoT Enterprise LTSC 2021 |
| Network | Default Switch (NAT) |
| Nested Virtualization | Enabled (required for AKS Edge) |

## 2.3 Enable Nested Virtualization

```powershell
# On workstation (with VM stopped)
Set-VMProcessor -VMName "IPC-Factory-01" -ExposeVirtualizationExtensions $true
```

## 2.4 VM Creation (Reference)

```powershell
# On workstation - Create the Demo VM
$VMName = "IPC-Factory-01"
$VHDPath = "E:\Factory-VMs\Factory-VMs\$VMName.vhdx"

# Create VM
New-VM -Name $VMName `
  -MemoryStartupBytes 8GB `
  -NewVHDPath $VHDPath `
  -NewVHDSizeBytes 60GB `
  -Generation 1 `
  -SwitchName "Default Switch"

# Configure VM
Set-VMProcessor -VMName $VMName -Count 4
Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $false

# Enable nested virtualization
Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true

# Start VM
Start-VM -Name $VMName
```

---

# 3. AKS Edge Essentials

## 3.1 What is AKS Edge Essentials?

AKS Edge Essentials is Microsoft's lightweight Kubernetes distribution for Windows IoT devices. It runs K3s (a CNCF-certified Kubernetes distribution) inside a Linux VM managed by Windows.

| Property | Value |
|----------|-------|
| Kubernetes Distribution | K3s |
| Linux VM | Mariner (CBL-Mariner) |
| Resource Footprint | ~4 GB RAM, ~20 GB disk |
| Container Runtime | containerd |

## 3.2 Installation

AKS Edge Essentials installation process:

1. Download MSI from `https://aka.ms/aks-edge/k3s-msi`
2. Install with default options
3. Deploy single-machine cluster

```powershell
# On IPC-Factory-01 VM - Download and install AKS Edge
$downloadUrl = "https://aka.ms/aks-edge/k3s-msi"
$installerPath = "$env:TEMP\AksEdge-K3s.msi"

Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn" -Wait
```

## 3.3 Deployment Configuration

**File:** `C:\ProgramData\AksEdge\aksedge-config.json` (on VM)

```json
{
  "SchemaVersion": "1.14",
  "Version": "1.0",
  "DeploymentType": "SingleMachineCluster",
  "Init": {
    "ServiceIPRangeSize": 10
  },
  "Network": {
    "InternetDisabled": false
  },
  "User": {
    "AcceptEula": true,
    "AcceptOptionalTelemetry": false
  },
  "Machines": [
    {
      "LinuxNode": {
        "CpuCount": 4,
        "MemoryInMB": 4096,
        "DataSizeInGB": 20
      }
    }
  ]
}
```

## 3.4 Deploy the Cluster

```powershell
# On IPC-Factory-01 VM
Import-Module AksEdge

# Deploy single-machine cluster
New-AksEdgeDeployment -JsonConfigFilePath "C:\ProgramData\AksEdge\aksedge-config.json"

# Wait for deployment (5-10 minutes)
```

## 3.5 Verification Commands

Run on **IPC-Factory-01 VM**:

```powershell
# Check AKS Edge deployment status
Import-Module AksEdge
Get-AksEdgeDeploymentInfo

# Check Kubernetes nodes
kubectl get nodes

# Expected output:
# NAME                      STATUS   ROLES                  AGE   VERSION
# ipc-factory-01-ledge      Ready    control-plane,master   Xd    v1.28.x+k3s1

# Check all pods across namespaces
kubectl get pods -A

# Check cluster info
kubectl cluster-info
```

## 3.6 Access kubectl from workstation

```powershell
# Copy kubeconfig from VM to workstation
$VMKubeConfig = "\\IPC-Factory-01\c$\Users\Administrator\.kube\config"
$LocalKubeConfig = "$env:USERPROFILE\.kube\config-ipc-factory"

Copy-Item -Path $VMKubeConfig -Destination $LocalKubeConfig

# Use with kubectl
$env:KUBECONFIG = $LocalKubeConfig
kubectl get nodes
```

---

# 4. Azure Arc Connection

## 4.1 What is Azure Arc?

Azure Arc extends Azure management capabilities to resources outside Azure—including Kubernetes clusters running on-premises or at the edge.

| Capability | Benefit |
|------------|---------|
| Single pane of glass | Manage all IPCs from Azure Portal |
| GitOps | Deploy configurations from Git repositories |
| Policy | Apply Azure Policy to edge clusters |
| Monitoring | Stream logs and metrics to Azure Monitor |

## 4.2 Arc-Connected Cluster Details

| Property | Value |
|----------|-------|
| Cluster Name | `aks-edge-ipc-factory-01` |
| Resource Group | `rg-ipc-platform-arc` |
| Location | Central US |
| Distribution | AKS Edge Essentials |
| Infrastructure | Windows Hyper-V |

## 4.3 Arc Connection Process

```powershell
# On workstation (with Azure CLI logged in and kubeconfig configured)

# Login to Azure
az login

# Set subscription
az account set --subscription "<your-subscription-id>"

# Connect cluster to Arc
az connectedk8s connect `
  --name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --location "centralus" `
  --kube-config "$env:USERPROFILE\.kube\config-ipc-factory"
```

## 4.4 Verification

**From workstation (Azure CLI):**
```powershell
az connectedk8s show `
  --name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --query "connectivityStatus" -o tsv

# Expected: Connected
```

**From Azure Portal:**
1. Navigate to: Azure Arc → Kubernetes clusters
2. Click on `aks-edge-ipc-factory-01`
3. Verify Status shows "Connected"

**From VM:**
```powershell
# Check Arc agents
kubectl get pods -n azure-arc

# Expected output shows running pods:
# NAME                                         READY   STATUS    RESTARTS   AGE
# clusterconnect-agent-xxx                     1/1     Running   0          Xd
# extension-manager-xxx                        1/1     Running   0          Xd
# flux-logs-agent-xxx                          1/1     Running   0          Xd
# resource-sync-agent-xxx                      1/1     Running   0          Xd
```

## 4.5 Troubleshooting Arc Connection

```powershell
# Check Arc agent logs
kubectl logs -n azure-arc -l app.kubernetes.io/name=clusterconnect-agent

# Check outbound connectivity
Test-NetConnection -ComputerName "management.azure.com" -Port 443
Test-NetConnection -ComputerName "centralus.his.arc.azure.com" -Port 443

# Force reconnect if needed
az connectedk8s update `
  --name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc"
```

---

# 5. Kubernetes Namespaces

| Namespace | Purpose | Managed By |
|-----------|---------|------------|
| `ipc-workloads` | Business application containers | GitOps |
| `flux-system` | Flux controllers | Azure Arc |
| `azure-arc` | Arc connectivity agents | Azure Arc |
| `kube-system` | Kubernetes core (API, DNS, CNI) | K3s |

## 5.1 Create Workloads Namespace

```powershell
# On VM
kubectl create namespace ipc-workloads

# Verify
kubectl get namespaces
```

## 5.2 Namespace Labels (for GitOps)

```yaml
# kubernetes/workloads/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ipc-workloads
  labels:
    managed-by: flux
    environment: poc
```

---

# 6. ACR Pull Secret

Kubernetes needs credentials to pull images from the private Azure Container Registry.

## 6.1 Secret Details

**Secret Name:** `acr-pull-secret`  
**Namespace:** `ipc-workloads`  
**Type:** `kubernetes.io/dockerconfigjson`

## 6.2 Create the Secret

```powershell
# Get ACR password first
$ACR_PASSWORD = az acr credential show --name <your-acr-name> --query "passwords[0].value" -o tsv

# On VM - Create the secret
kubectl create secret docker-registry acr-pull-secret `
  --namespace ipc-workloads `
  --docker-server=<your-acr-name>.azurecr.io `
  --docker-username=<your-acr-name> `
  --docker-password=$ACR_PASSWORD
```

## 6.3 Verify the Secret

```powershell
kubectl get secrets -n ipc-workloads

# Expected:
# NAME              TYPE                             DATA   AGE
# acr-pull-secret   kubernetes.io/dockerconfigjson   1      Xd
```

## 6.4 Usage in Deployments

All workload deployments must reference this secret:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: my-container
          image: <your-acr-name>.azurecr.io/my-image:latest
```

---

---

# 7. Container Registry Authentication

## 7.1 Authentication Strategy

### Current (PoC)

Uses Kubernetes Secret for ACR authentication (`imagePullSecrets`):

```yaml
imagePullSecrets:
  - name: acr-pull-secret
```

### Production Best Practice

Use Arc agent's Managed Identity with AcrPull role assignment:

1. No secrets in cluster
2. No credential rotation required
3. Automatic token refresh
4. Audit logging via Azure AD
5. **Implementation**: Assign `AcrPull` role to the Arc Connected Machine identity.

---

# 8. Operational Procedures

## 7.1 Startup Sequence

```powershell
# 1. On workstation - Start the VM
Start-VM -Name "IPC-Factory-01"

# 2. Wait 2 minutes for Windows to boot

# 3. On VM - Start AKS Edge Linux node (if not auto-starting)
Import-Module AksEdge
Start-AksEdgeNode -NodeType Linux

# 4. Wait 60 seconds, then verify
kubectl get nodes
kubectl get pods -n ipc-workloads
```

## 7.2 Shutdown Sequence

```powershell
# 1. On VM - Stop AKS Edge gracefully
Import-Module AksEdge
Stop-AksEdgeNode -NodeType Linux

# 2. Wait for completion

# 3. On workstation - Stop the VM
Stop-VM -Name "IPC-Factory-01"
```

## 7.3 Quick Status Check

```powershell
# On VM - Full status check
Write-Host "=== Node Status ===" -ForegroundColor Cyan
kubectl get nodes

Write-Host "`n=== Workload Pods ===" -ForegroundColor Cyan
kubectl get pods -n ipc-workloads

Write-Host "`n=== Flux Status ===" -ForegroundColor Cyan
kubectl get gitrepositories -n flux-system

Write-Host "`n=== Arc Status ===" -ForegroundColor Cyan
kubectl get pods -n azure-arc | Select-Object -First 5
```

## 7.4 Check Resource Usage

```powershell
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -n ipc-workloads

# Detailed node info
kubectl describe node ipc-factory-01-ledge
```

## 7.5 View Workload Logs

```powershell
# Logs for a specific pod
kubectl logs -n ipc-workloads <pod-name>

# Follow logs in real-time
kubectl logs -n ipc-workloads <pod-name> -f

# Logs for all pods with a label
kubectl logs -n ipc-workloads -l app=health-monitor
```

## 7.6 Restart a Workload

```powershell
# Restart a deployment (rolling restart)
kubectl rollout restart deployment/<deployment-name> -n ipc-workloads

# Check rollout status
kubectl rollout status deployment/<deployment-name> -n ipc-workloads
```

## 7.7 Emergency: Delete and Recreate Workloads

```powershell
# Delete all workloads (Flux will recreate them)
kubectl delete all --all -n ipc-workloads

# Force Flux to reconcile immediately
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# Watch pods come back up
kubectl get pods -n ipc-workloads -w
```

---

*End of Edge Deployment Section*

**Previous:** [02-Golden-Image-Pipeline.md](02-Golden-Image-Pipeline.md)  
**Next:** [04-GitOps-Configuration.md](04-GitOps-Configuration.md)
