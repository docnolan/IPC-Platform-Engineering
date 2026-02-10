# GitOps Configuration
# Flux Setup and Kubernetes Manifest Management

---

# Table of Contents

1. [Understanding GitOps](#1-understanding-gitops)
2. [Flux Extension](#2-flux-extension)
3. [GitOps Configuration](#3-gitops-configuration)
4. [Azure DevOps PAT Authentication](#4-azure-devops-pat-authentication)
5. [Repository Structure](#5-repository-structure)
6. [Base Kubernetes Manifests](#6-base-kubernetes-manifests)
7. [Verification](#7-verification)
8. [Operational Commands](#8-operational-commands)
9. [Troubleshooting](#9-troubleshooting)

---

# 1. Understanding GitOps

## 1.1 What is GitOps?

GitOps is a methodology where:
- **Git is the source of truth** for infrastructure and application configuration
- **Changes are made via pull requests**, not direct commands
- **An agent (Flux) watches the repo** and applies changes automatically
- **The cluster converges to the desired state** defined in Git

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  Developer          │────►│  Azure DevOps       │────►│   Flux Agent        │
│  pushes YAML        │     │  Git Repo           │     │  (on cluster)       │
│  to repo            │     │                     │     │  pulls changes      │
└─────────────────────┘     └─────────────────────┘     └─────────┬───────────┘
                                                                  │
                                                                  ▼
                                                        ┌─────────────────────┐
                                                        │  Kubernetes         │
                                                        │  applies config     │
                                                        └─────────────────────┘
```

## 1.2 Why GitOps Matters for IPC

> "When we need to update software on 50 deployed panels, we change one YAML file in Git. Every panel automatically picks up the change within 5 minutes—no truck rolls, no remote desktop sessions."

| Benefit | Impact |
|---------|--------|
| Zero-touch updates | No physical access required |
| Version control | Every change is tracked, auditable |
| Rollback capability | `git revert` undoes deployment |
| Peer review | PRs enforce approval before deployment |
| Consistency | All panels get identical configuration |

---

# 2. Flux Extension

## 2.1 Overview

| Property | Value |
|----------|-------|
| Extension Name | `flux` |
| Extension Type | `microsoft.flux` |
| Scope | Cluster |
| Status | Installed |

## 2.2 Install Flux Extension

On **workstation** (not the VM), run:

```powershell
# Install the Flux extension on your Arc-connected cluster
az k8s-extension create `
  --name flux `
  --extension-type microsoft.flux `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --scope cluster
```

This takes 2-3 minutes. Wait for provisioning to complete.

## 2.3 Verify Extension Installation

```powershell
# Check extension status
az k8s-extension show `
  --name flux `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --query "provisioningState" -o tsv

# Expected: Succeeded
```

## 2.4 Verify Flux Pods on Cluster

On **IPC-Factory-01 VM**:

```powershell
kubectl get pods -n flux-system

# Expected output:
# NAME                                       READY   STATUS    RESTARTS   AGE
# fluxconfig-agent-xxx                       1/1     Running   0          Xd
# fluxconfig-controller-xxx                  1/1     Running   0          Xd
# helm-controller-xxx                        1/1     Running   0          Xd
# kustomize-controller-xxx                   1/1     Running   0          Xd
# notification-controller-xxx                1/1     Running   0          Xd
# source-controller-xxx                      1/1     Running   0          Xd
```

---

# 3. GitOps Configuration

## 3.1 Configuration Details

| Property | Value |
|----------|-------|
| Configuration Name | `ipc-platform-config` |
| Repository URL | `https://dev.azure.com/<your-org>/IPC-Platform-Engineering/_git/IPC-Platform-Engineering` |
| Branch | `main` |
| Sync Path | `./kubernetes/workloads` |
| Sync Interval | 5 minutes |
| Authentication | Azure DevOps PAT |
| Prune | Enabled (removes deleted resources) |

## 3.2 Create GitOps Configuration

```powershell
# Create the GitOps configuration (Flux source + kustomization)
az k8s-configuration flux create `
  --name "ipc-platform-config" `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --namespace "flux-system" `
  --scope cluster `
  --url "https://dev.azure.com/<your-org>/IPC-Platform-Engineering/_git/IPC-Platform-Engineering" `
  --branch "main" `
  --kustomization name=workloads path=./kubernetes/workloads prune=true sync_interval=5m
```

## 3.3 Parameters Explained

| Parameter | Description |
|-----------|-------------|
| `--url` | Your Azure DevOps Git repo URL |
| `--branch` | Branch to watch (main) |
| `--kustomization path` | Folder in repo containing Kubernetes manifests |
| `--sync_interval` | How often Flux checks for changes (5 minutes) |
| `--prune` | Remove resources that are deleted from Git |
| `--scope cluster` | Configuration applies to entire cluster |

---

# 4. Azure DevOps PAT Authentication

Flux needs read access to your private repo.

## 4.1 Create Personal Access Token

1. In Azure DevOps, click your profile icon (top right) → **Personal access tokens**
2. Click **+ New Token**
3. Configure:
   - **Name:** `flux-gitops-readonly`
   - **Organization:** `<your-org>`
   - **Expiration:** 90 days (or custom)
   - **Scopes:** Custom defined → **Code: Read**
4. Click **Create** and **copy the token immediately**

## 4.2 Update Configuration with Credentials

```powershell
# Update with PAT authentication
az k8s-configuration flux update `
  --name "ipc-platform-config" `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --https-user "<your-org>" `
  --https-key "YOUR_PAT_TOKEN_HERE"
```

## 4.3 PAT Renewal Reminder

PATs expire. Create a calendar reminder to renew before expiration:

```powershell
# Check when PAT expires (in Azure DevOps portal)
# Then update the GitOps configuration with new PAT
az k8s-configuration flux update `
  --name "ipc-platform-config" `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --https-key "NEW_PAT_TOKEN"
```

---

# 5. Repository Structure

## 5.1 Authentication Strategy

### Current (PoC)

| Method | Credential | Expiration | Rotation |
|--------|------------|------------|----------|
| PAT | flux-gitops-readonly | 90 days | Manual |

### Production Target

| Method | Credential | Expiration | Rotation |
|--------|------------|------------|----------|
| Workload Identity | mi-flux-gitops | Never | Automatic |

### Migration Path

The PoC uses PAT authentication for simplicity. Production deployments should migrate to Workload Identity Federation for:

- **Zero secrets:** No credentials stored in cluster
- **No expiration:** Tokens are short-lived and auto-refreshed
- **Audit trail:** Azure AD logs all token exchanges
- **Compliance:** Meets NIST 800-171 IA-5 (Authenticator Management)

## 5.2 Kubernetes Manifest Layout

```
C:\Projects\IPC-Platform-Engineering\
└── kubernetes/
    └── workloads/
        ├── kustomization.yaml      # Main kustomization (lists all resources)
        ├── namespace.yaml          # ipc-workloads namespace
        │
        │   # ══════════════════════════════════════════════════════════
        │   # PRODUCTION WORKLOADS (Ship to Customers)
        │   # ══════════════════════════════════════════════════════════
        │
        ├── opcua-gateway/          # [Production] OPC-UA to IoT Hub
        │   ├── kustomization.yaml
        │   ├── deployment.yaml
        │   └── configmap.yaml
        │
        ├── health-monitor/         # [Production] System health metrics
        │   ├── kustomization.yaml
        │   └── deployment.yaml
        │
        ├── log-forwarder/          # [Production] Security audit logs
        │   ├── kustomization.yaml
        │   └── deployment.yaml
        │
        ├── anomaly-detection/      # [Production] Edge ML alerting
        │   ├── kustomization.yaml
        │   └── deployment.yaml
        │
        ├── test-data-collector/    # [Production] Test results upload
        │   ├── kustomization.yaml
        │   └── deployment.yaml
        │
        │   # ══════════════════════════════════════════════════════════
        │   # POC SIMULATORS (Demo Only - Not for Production)
        │   # ══════════════════════════════════════════════════════════
        │
        ├── opcua-simulator/        # [Simulator] Generic PLC tags
        │   ├── kustomization.yaml
        │   └── deployment.yaml
        │
        ├── ev-battery-simulator/   # [Simulator] 96-cell battery pack
        │   ├── kustomization.yaml
        │   └── deployment.yaml
        │
        ├── vision-simulator/       # [Simulator] Quality inspection events
        │   ├── kustomization.yaml
        │   └── deployment.yaml
        │
        ├── motion-simulator/       # [Simulator] 3-axis gantry OPC-UA server
        │   ├── kustomization.yaml
        │   └── deployment.yaml
        │
        └── motion-gateway/         # [Simulator] Motion OPC-UA to IoT Hub
            ├── kustomization.yaml
            └── deployment.yaml
```

## 5.2 How Flux Processes This Structure

1. Flux watches the `kubernetes/workloads/` folder
2. It reads `kustomization.yaml` to find all resources
3. Each subfolder has its own `kustomization.yaml` for that workload
4. Flux applies all manifests to the cluster
5. If you delete a file from Git, Flux removes it from the cluster (pruning)

---

# 6. Base Kubernetes Manifests

## 6.1 Main Kustomization

**File:** `kubernetes/workloads/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ipc-workloads

resources:
  - namespace.yaml
  
  # Production Workloads (Ship to Customers)
  - opcua-gateway/
  - health-monitor/
  - log-forwarder/
  - anomaly-detection/
  - test-data-collector/
  
  # PoC Simulators (Demo Only)
  - opcua-simulator/
  - ev-battery-simulator/
  - vision-simulator/
  - motion-simulator/
  - motion-gateway/
```

## 6.2 Namespace Definition

**File:** `kubernetes/workloads/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ipc-workloads
  labels:
    managed-by: flux
    purpose: edge-workloads
    environment: poc
```

## 6.3 Workload Kustomization Example

**File:** `kubernetes/workloads/health-monitor/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
```

## 6.4 Simulator Kustomization Example

**File:** `kubernetes/workloads/ev-battery-simulator/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
```

## 6.5 Initial Commit

```powershell
# From C:\Projects\IPC-Platform-Engineering
git add kubernetes/
git commit -m "Add base Kubernetes configuration for GitOps"
git push origin main
```

---

# 7. Verification

## 7.1 Check GitRepository Status

On **IPC-Factory-01 VM**:

```powershell
kubectl get gitrepositories -n flux-system

# Expected output:
# NAME                   URL                                    READY   STATUS
# ipc-platform-config    https://dev.azure.com/...              True    Fetched revision: main/abc123
```

## 7.2 Check Kustomization Status

```powershell
kubectl get kustomizations -n flux-system

# Expected output:
# NAME                        READY   STATUS
# ipc-platform-config-workloads   True    Applied revision: main/abc123
```

## 7.3 Check Namespace Was Created

```powershell
kubectl get namespaces

# Expected:
# NAME              STATUS   AGE
# ipc-workloads     Active   <5m
# flux-system       Active   <10m
# azure-arc         Active   <10m
# ...
```

## 7.4 Check Workloads Are Running

```powershell
kubectl get pods -n ipc-workloads

# Expected (all 10 workloads running):
# NAME                                   READY   STATUS    RESTARTS   AGE
# opcua-gateway-xxx                      1/1     Running   0          Xm
# health-monitor-xxx                     1/1     Running   0          Xm
# log-forwarder-xxx                      1/1     Running   0          Xm
# anomaly-detection-xxx                  1/1     Running   0          Xm
# test-data-collector-xxx                1/1     Running   0          Xm
# opcua-simulator-xxx                    1/1     Running   0          Xm
# ev-battery-simulator-xxx               1/1     Running   0          Xm
# vision-simulator-xxx                   1/1     Running   0          Xm
# motion-simulator-xxx                   1/1     Running   0          Xm
# motion-gateway-xxx                     1/1     Running   0          Xm
```

## 7.5 Check by Workload Type

```powershell
# Production workloads only
kubectl get pods -n ipc-workloads -l workload-type=production

# Simulators only
kubectl get pods -n ipc-workloads -l workload-type=simulator
```

---

# 8. Operational Commands

## 8.1 Force Immediate Sync

Don't wait 5 minutes for automatic sync:

```powershell
# Force GitRepository reconciliation
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# Force Kustomization reconciliation
kubectl annotate kustomization ipc-platform-config-workloads -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

## 8.2 Check Sync Status

```powershell
# Detailed GitRepository status
kubectl describe gitrepository ipc-platform-config -n flux-system

# Detailed Kustomization status
kubectl describe kustomization ipc-platform-config-workloads -n flux-system
```

## 8.3 View Flux Logs

```powershell
# Source controller logs (Git fetching)
kubectl logs -n flux-system -l app=source-controller

# Kustomize controller logs (applying manifests)
kubectl logs -n flux-system -l app=kustomize-controller
```

## 8.4 Suspend/Resume Sync

```powershell
# Suspend GitOps sync (useful during maintenance)
az k8s-configuration flux update `
  --name "ipc-platform-config" `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --suspend true

# Resume GitOps sync
az k8s-configuration flux update `
  --name "ipc-platform-config" `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --suspend false
```

---

# 9. Troubleshooting

## 9.1 GitRepository Not Ready

**Symptoms:** `kubectl get gitrepositories -n flux-system` shows `READY: False`

**Common causes:**
1. Invalid PAT token
2. Repository URL incorrect
3. Network connectivity issues

**Resolution:**
```powershell
# Check detailed status
kubectl describe gitrepository ipc-platform-config -n flux-system

# Look for error messages like:
# - "authentication required"
# - "repository not found"
# - "timeout"
```

## 9.2 Kustomization Failing

**Symptoms:** Kustomization shows errors

```powershell
# Get detailed error
kubectl describe kustomization ipc-platform-config-workloads -n flux-system

# Common issues:
# - Invalid YAML syntax
# - Missing resources referenced in kustomization.yaml
# - Image pull errors
```

## 9.3 Pods Not Starting

```powershell
# Check pod events
kubectl describe pod <pod-name> -n ipc-workloads

# Check for:
# - ImagePullBackOff (ACR credentials wrong)
# - CrashLoopBackOff (application error)
# - Pending (resource constraints)
```

## 9.4 Reset GitOps Configuration

If things are badly broken, delete and recreate:

```powershell
# Delete the configuration
az k8s-configuration flux delete `
  --name "ipc-platform-config" `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --yes

# Recreate with fresh credentials
az k8s-configuration flux create `
  --name "ipc-platform-config" `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --namespace "flux-system" `
  --scope cluster `
  --url "https://dev.azure.com/<your-org>/IPC-Platform-Engineering/_git/IPC-Platform-Engineering" `
  --branch "main" `
  --kustomization name=workloads path=./kubernetes/workloads prune=true sync_interval=5m `
  --https-user "<your-org>" `
  --https-key "YOUR_PAT_TOKEN"
```

## 9.5 Verify Outbound Connectivity

```powershell
# On VM - Test connectivity to Azure DevOps
Test-NetConnection -ComputerName "dev.azure.com" -Port 443

# Test connectivity to Azure management
Test-NetConnection -ComputerName "management.azure.com" -Port 443
```

---

# 10. Flux Image Automation

Flux Image Automation enables automatic container image updates when new versions are pushed to ACR. This eliminates manual manifest edits when pipelines build new image tags.

## 10.1 Overview

| Component | Purpose |
|-----------|---------|
| **ImageRepository** | Scans ACR for new image tags at regular intervals |
| **ImagePolicy** | Defines which tags to select (e.g., semver pattern) |
| **ImageUpdateAutomation** | Commits updated image tags back to Git |

## 10.2 How It Works

```
┌─────────────┐    ┌──────────────────┐    ┌─────────────────┐    ┌──────────────┐
│ CI Pipeline │───►│ ACR Push         │───►│ Flux Detects    │───►│ Git Commit   │
│ Builds Image│    │ New Tag (v1.0.8) │    │ New Image       │    │ Updates YAML │
└─────────────┘    └──────────────────┘    └─────────────────┘    └──────────────┘
                                                                          │
                                                                          ▼
                                                                  ┌──────────────┐
                                                                  │ Flux Deploys │
                                                                  │ New Version  │
                                                                  └──────────────┘
```

## 10.3 Configuration Files

All image automation resources are in `kubernetes/flux-system/image-automation/`:

```
kubernetes/flux-system/image-automation/
├── kustomization.yaml
├── image-repositories.yaml    # ImageRepository for each workload
├── image-policies.yaml        # ImagePolicy for each workload
└── image-update-automation.yaml
```

## 10.4 ImageRepository Example

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: health-monitor
  namespace: flux-system
spec:
  image: <your-acr-name>.azurecr.io/ipc/health-monitor
  interval: 1m
  secretRef:
    name: acr-credentials
```

## 10.5 ImagePolicy Example

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: health-monitor
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: health-monitor
  policy:
    semver:
      range: ">=1.0.0"
```

## 10.6 Deployment Markers

For image automation to work, deployments must include special comments:

```yaml
spec:
  containers:
    - name: health-monitor
      image: <your-acr-name>.azurecr.io/ipc/health-monitor:v1.0.7 # {"$imagepolicy": "flux-system:health-monitor"}
```

The comment tells Flux which ImagePolicy controls this image tag.

## 10.7 Verification Commands

```powershell
# Check ImageRepository status
kubectl get imagerepositories -n flux-system

# Check ImagePolicy status  
kubectl get imagepolicies -n flux-system

# Check ImageUpdateAutomation status
kubectl get imageupdateautomations -n flux-system

# View latest detected image
kubectl describe imagerepository health-monitor -n flux-system
```

## 10.8 Troubleshooting Image Automation

| Symptom | Cause | Solution |
|---------|-------|----------|
| ImageRepository shows "not ready" | ACR credentials invalid | Rotate `acr-credentials` secret |
| Images not updating | Policy not matching tags | Check semver range matches tag format |
| Git commits failing | PAT expired or no write access | Update Flux Git credentials |
| Wrong image selected | Multiple tags match policy | Narrow semver range |

---

# 11. Required Secrets Reference

All workloads require specific Kubernetes secrets. This table provides a complete reference:

| Secret Name | Namespace | Keys | Used By |
|-------------|-----------|------|---------|
| `acr-pull-secret` | ipc-workloads | (docker-registry) | All workloads |
| `acr-credentials` | flux-system | (docker-registry) | Image automation |
| `iot-hub-connection` | ipc-workloads | `connectionString` | Gateway workloads |
| `log-analytics-connection` | ipc-workloads | `workspaceId`, `key` | health-monitor, log-forwarder |
| `blob-storage-connection` | ipc-workloads | `connectionString` | test-data-collector |

### Create ACR Pull Secret

```powershell
# Get ACR credentials
$acrPassword = az acr credential show --name <your-acr-name> --query "passwords[0].value" -o tsv

kubectl create secret docker-registry acr-pull-secret `
  --namespace ipc-workloads `
  --docker-server=<your-acr-name>.azurecr.io `
  --docker-username=<your-acr-name> `
  --docker-password=$acrPassword
```

### Bootstrap All Secrets

Use the Bootstrap-Secrets.ps1 script to create all required secrets:

```powershell
.\scripts\Bootstrap-Secrets.ps1 -Verbose
```

---

*End of GitOps Configuration Section*

**Previous:** [03-Edge-Deployment.md](03-Edge-Deployment.md)  
**Next:** [05-Workloads-OPC-UA.md](05-Workloads-OPC-UA.md)

