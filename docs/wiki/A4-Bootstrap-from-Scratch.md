# A4. Bootstrap from Scratch ("Nuke and Pave")

**Status**: Draft
**Owner**: Platform Engineering

## 1. Overview

This document defines the "Nuke and Pave" procedure for the IPC Edge Platform. This process serves two critical functions:
1.  **Disaster Recovery (DR)**: The ability to completely restore the environment from a "scorched earth" state.
2.  **Environment Templating**: The ability to spin up *new* environments using this repository as a template.

### 1.1 Timing Goals

| Scenario | Description | Target Time |
| :--- | :--- | :--- |
| **Recovery** | Re-provisioning infrastructure using an existing Golden Image (e.g., in Azure Compute Gallery) and existing Terraform State backup. | **< 30 Minutes** |
| **Full Rebuild** | Starting from absolute zero. Includes building the Golden Image (Packer) and bootstrapping empty State. | **~ 50 Minutes** |

## 2. Architecture

The bootstrap process is orchestrated by a single PowerShell script (`scripts/bootstrap.ps1`) which executes in **Layers**.

```mermaid
graph TD
    User[User / Operator] -->|Customer Profile| Script[bootstrap.ps1]
    
    subgraph Layer 0: Pre-flight
        Script -->|Check| Net[Connectivity]
        Script -->|Load| Config[customer.json]
    end

    subgraph Layer 1: Infrastructure
        Script -->|Terraform| Azure[Azure Resources]
        Azure -->|State| SA[Storage Account]
        Azure -->|Secrets| KV[Key Vault]
    end

    subgraph Layer 2: DevOps
        Script -->|Az CLI| AzDO[Azure DevOps]
        AzDO -->|Seed| Envs[Environments (Dev/Prod)]
        AzDO -->|Create| SPN[Service Connection]
    end

    subgraph Layer 3: Image
        Script -->|Packer| Gallery[Azure Compute Gallery]
    end

    subgraph Layer 4: Edge
        Script -->|Arm/Bicep| VM[Edge VM]
        VM -->|Pull| Gallery
        VM -->|Connect| Arc[Azure Arc]
    end

    subgraph Layer 5: Workloads
        Arc -->|Flux| GitOps[GitOps Sync]
        GitOps -->|Deploy| Pods[Workloads]
    end
```

## 3. Product Template Strategy

To support multiple customers, this repository is a **Template**. No customer-specific data is hardcoded check scripts.

### 3.1 `customer.json`
Every execution requires a customer profile.

```json
{
  "CustomerName": "IPC",
  "Environment": "PoC",
  "Location": "centralus",
  "SubscriptionId": "00000000-0000-0000-0000-000000000000",
  "SkuSize": "Standard_D4s_v5"
}
```

The bootstrap script authenticates to the specified Subscription and names resources using the pattern: `ipc-<customer>-<env>-<resource>`.

## 4. Execution Guide

### 4.1 Prerequisites
*   **PowerShell 7+**
*   **Azure CLI** (`az login` performed)
*   **Terraform** (v1.5+)
*   **Packer** (v1.9+)
*   **Kubectl**

### 4.2 Usage

**Standard Recovery Run (Uses existing image if found):**
```powershell
./scripts/bootstrap.ps1 -CustomerName "IPC"
```

**Force Full Rebuild (Rebuilds Image):**
```powershell
./scripts/bootstrap.ps1 -CustomerName "IPC" -Layer "All" -Force
```

**Destroy (Teardown):**
```powershell
./scripts/bootstrap.ps1 -CustomerName "IPC" -Destroy
```

## 5. Implementation Stages (Layers)

### Layer 0: Pre-flight & Safety
*   **Network Check**: Validates TCP connectivity to `management.azure.com`, `dev.azure.com`, etc.
*   **Auth Check**: Verifies current `az account` matches the target Subscription ID.
*   **Cleanup**: If `-Destroy` is passed, nukes the Resource Group and AzDO Project.

### Layer 1: Infrastructure (Terraform)
*   **State Bootstrap**: If the Terraform State Storage Account doesn't exist, it is created via Azure CLI and then **Imported** into Terraform.
*   **Apply**: Provisions Networking, ACR, Key Vault, and Log Analytics.

### Layer 2: DevOps (AzDO)
*   **Project**: Creates/Updates the Azure DevOps Project.
*   **Identity**: Creates a Service Principal with **90-day expiry**.
    *   *Security Note*: The Client Secret is passed directly to the Service Connection resource and never logged.
*   **Seeding**: pre-creates `Dev`, `Alpha`, `Beta`, `Prod` environments in the Pipelines UI.

### Layer 3: Golden Image
*   **Check**: Looks for `ipc-image-<version>` in the Compute Gallery.
*   **Build**: If missing, runs `packer build`. This is the longest step (~20m).

### Layer 4: Edge Deployment
*   **Provision**: Deploys the Edge VM using the Golden Image.
*   **Onboard**: Scripts the `azcmagent connect` to project the VM into Azure Arc.

### Layer 5: GitOps & Workloads
*   **Flux**: Bootstraps the Flux extension on the Arc-Connected Machine.
*   **Health Check**: Polls `kubectl get pods` until all expected workloads are `Running`.

## 6. Validation (Definition of Done)
The process is only successful when:
1.  **Workloads Healthy**: All business pods are Running.
2.  **Telemetry Flowing**: Logs are visible in Azure Monitor.
3.  **Metrics Generated**: `bootstrap-metrics.json` is produced containing the duration of each layer.
