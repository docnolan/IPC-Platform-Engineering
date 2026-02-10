# CI/CD Pipelines

This page documents the Azure DevOps pipelines that enable **Zero-Touch Updates**—the ability to update software on deployed IPCs through Git commits rather than truck rolls.

---

## Overview

The platform uses a **Golden Pipeline** standard to ensure every deployed workload is secure, compliant, and traceable.

| Pipeline Component | Technology | Purpose |
|-------------------|------------|---------|
| **Build** | Docker (Linux Agents) | Multi-stage builds |
| **Scan** | Trivy | Vulnerability scanning (Fails on Critical) |
| **Sign** | Cosign | Digital signature for provenance |
| **Push** | Azure Container Registry | Artifact storage |
| **Deploy** | Flux (GitOps) | Continuous Delivery |

### Secure Software Supply Chain

```
Developer          Azure DevOps           ACR              Cluster
   │                    │                   │                  │
   │  1. Push Code      │                   │                  │
   │ ──────────────────►│                   │                  │
   │                    │ 2. Build Image    │                  │
   │                    │ 3. Scan (Trivy)   │                  │
   │                    │ 4. Sign (Cosign)  │                  │
   │                    │ 5. Push Image     │                  │
   │                    ├──────────────────►│                  │
   │                    │                   │                  │
   │                    │                   │ 6. Flux detects  │
   │                    │                   │ new image tag    │
   │                    │                   ├─────────────────►│
   │                    │                   │                  │
   │                    │                   │ 7. Cluster pulls │
   │                    │                   │ verifies sig &   │
   │                    │                   │ deploys          │
   │                    │                   │◄─────────────────┤
```

---

## Container Build Pipeline (Golden Standard)

Each workload manages its own lifecycle via a dedicated `azure-pipelines.yml`. This decouples failures and allows independent versioning.

### Example: OPC-UA Gateway

**Path:** `docker/opcua-gateway/azure-pipelines.yml`

```yaml
name: $(Major).$(Minor).$(Rev)

trigger:
  paths:
    include:
      - docker/opcua-gateway/**

variables:
  - name: Major
    value: 1
  - name: Minor
    value: 0
  - name: Rev
    value: $[counter(format('{0}.{1}', variables['Major'], variables['Minor']), 0)]
  - name: workloadName
    value: 'ipc/opcua-gateway'
  - name: dockerContext
    value: 'docker/opcua-gateway'
  - group: Security-Keys

pool:
  vmImage: 'ubuntu-latest'

jobs:
  - job: BuildAndDeliver
    displayName: 'Build, Scan, Sign, Push'
    steps:
      - task: DownloadSecureFile@1
        name: cosignKey
        displayName: 'Download Cosign Private Key'
        inputs:
          secureFile: 'cosign.key'

      - template: ../../pipelines/templates/docker-build-scan-sign.yml
        parameters:
          workloadName: $(workloadName)
          dockerContext: $(dockerContext)
          imageTag: 'v$(Major).$(Minor).$(Rev)'
          cosignKeyPath: $(cosignKey.secureFilePath)
```

---

## Build Template (Security Enabled)

This reusable template handles the heavy lifting of building, scanning, and signing.

### File Location

**Path:** `C:\Projects\IPC-Platform-Engineering\pipelines\templates\docker-build-scan-sign.yml`

### Template YAML Structure

```yaml
parameters:
  - name: workloadName
    type: string
  - name: dockerContext
    type: string
  - name: imageTag
    type: string
  - name: cosignKeyPath
    type: string

steps:
  # 1. Build
  - task: Docker@2
    displayName: 'Build Image'
    inputs:
      command: 'build'
      # ...

  # 2. Scan (Trivy)
  - script: |
      wget .../trivy...
      ./trivy image --exit-code 1 --severity CRITICAL ...
    displayName: 'Security Scan (Trivy)'

  # 3. Push
  - task: Docker@2
    displayName: 'Push Image'
    inputs:
      command: 'push'
      # ...

  # 4. Sign (Cosign)
  - task: Docker@2
    displayName: 'Login to ACR'
    inputs:
      command: 'login'

  - script: |
      wget .../cosign...
      ./cosign sign --key ...
    displayName: 'Sign Image (Cosign)'
    env:
      COSIGN_PASSWORD: $(COSIGN_PASSWORD)
```

---

## Golden Image Pipeline

This pipeline validates Packer templates and triggers golden image builds.

### File Location

**Path:** `C:\Projects\IPC-Platform-Engineering\pipelines\build-golden-image.yml`

### Pipeline YAML

```yaml
# build-golden-image.yml
# Triggers when Packer templates or scripts change
# For production: builds image in Azure, stores in Compute Gallery

trigger:
  branches:
    include:
      - main
  paths:
    include:
      - packer/**

pr:
  branches:
    include:
      - main
  paths:
    include:
      - packer/**

pool:
  vmImage: 'windows-latest'

variables:
  - group: ipc-platform-variables
  - name: imageVersion
    value: '1.0.$(Build.BuildId)'

stages:
  - stage: Validate
    displayName: 'Validate Packer Configuration'
    jobs:
      - job: ValidatePacker
        displayName: 'Validate Packer Template'
        steps:
          - task: PowerShell@2
            displayName: 'Install Packer'
            inputs:
              targetType: 'inline'
              script: |
                choco install packer -y --no-progress
                $env:Path += ";C:\ProgramData\chocolatey\bin"
                packer --version

          - task: PowerShell@2
            displayName: 'Validate Packer Syntax'
            inputs:
              targetType: 'inline'
              script: |
                cd $(Build.SourcesDirectory)/packer/windows-iot-enterprise
                packer validate -syntax-only .
                Write-Host "Packer template syntax is valid"

  - stage: Build
    displayName: 'Build Golden Image'
    dependsOn: Validate
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - job: BuildImage
        displayName: 'Build Packer Image'
        timeoutInMinutes: 120
        steps:
          - task: PowerShell@2
            displayName: 'Log Build Metadata'
            inputs:
              targetType: 'inline'
              script: |
                Write-Host "##[section]Golden Image Build"
                Write-Host "Version: $(imageVersion)"
                Write-Host "Triggered by: $(Build.RequestedFor)"
                Write-Host "Commit: $(Build.SourceVersion)"
                
                # In production, this would trigger an Azure Packer build
                # For PoC, we document the process and validate syntax only
                Write-Host "##[warning]Production build would execute here"
                Write-Host "For PoC: Run 'packer build' manually on workstation"

          - task: PublishBuildArtifacts@1
            displayName: 'Publish Build Log'
            inputs:
              pathToPublish: '$(Build.SourcesDirectory)/packer'
              artifactName: 'packer-config'
```

### Pipeline Behavior

| Trigger | Action |
|---------|--------|
| PR to `main` touching `packer/**` | Validate syntax only |
| Merge to `main` touching `packer/**` | Validate + log (production would build) |

For the PoC, the pipeline validates syntax and documents the workflow. Full automated Azure-based builds require additional infrastructure (see Production Roadmap).

---

## Variable Groups

The pipelines rely on two variable groups:

### 1. `ipc-platform-variables` (General)

| Variable | Value |
|----------|-------|
| `acrName` | `<your-acr-name>` |

### 2. `Security-Keys` (Restricted)

| Variable | Description | Secret? |
|----------|-------------|---------|
| `COSIGN_PASSWORD` | Password for the Cosign private key | 🔒 Yes |
| `cosign.key` | Uploaded as a **Secure File**, not a variable | 🔒 Yes |

---

## Branch Policies

Branch policies enforce code review and validation before changes reach `main`.

### Configure Branch Policy on `main`

**Azure DevOps → Repos → Branches → main → ⋮ → Branch policies**

| Policy | Setting | Value |
|--------|---------|-------|
| Require minimum reviewers | Enabled | 1 reviewer |
| Allow requestors to approve | Disabled | — |
| Check for linked work items | Enabled | Required |
| Check for comment resolution | Enabled | Required |
| Build validation | Enabled | `build-containers` pipeline |
| Automatically include reviewers | Optional | Add yourself for PoC |

### Build Validation Configuration
1. Click **+ Add build policy**
2. Build pipeline: Select the specific workload pipeline (e.g., `opcua-gateway`)
3. Path filter: `/docker/opcua-gateway/*` (Important! Only trigger for relevant changes)
4. Trigger: Automatic
5. Policy requirement: Required
6. Display name: `OPC-UA Gateway Validation`

---

## Pipeline Setup Steps

### Step 1: Create Pipeline in Azure DevOps

1. Navigate to: Pipelines → New pipeline
2. Select: Azure Repos Git
3. Select: IPC-Platform-Engineering repository
4. Select: Existing Azure Pipelines YAML file
5. Branch: `main`
6. Path: `/docker/opcua-gateway/azure-pipelines.yml`
7. Click: **Save** (Do not run yet, we need permissions)

### Step 2: Configure Permissions

1. Run the pipeline once.
2. It will fail asking for permission to `Security-Keys` variable group and `cosign.key` secure file.
3. Click the "Authorize Resources" button on the run summary page.
4. Retry the run.

### Step 3: Configure Branch Policy

1. Navigate to: Repos → Branches
2. Click ⋮ on `main` branch → Branch policies
3. Add build validation linking to the new pipeline (see above).

---

## PR Workflow Demo

This workflow demonstrates Zero-Touch Updates in action.

### 1. Create Feature Branch

```powershell
cd C:\Projects\IPC-Platform-Engineering
git checkout -b feature/update-health-monitor
```

### 2. Make a Change

Edit `docker/health-monitor/src/monitor.py`:

```python
# Change the collection interval from 60 to 30 seconds
COLLECTION_INTERVAL = int(os.getenv("COLLECTION_INTERVAL", "30"))  # Changed from 60
```

### 3. Commit and Push

```powershell
git add .
git commit -m "Update health monitor collection interval to 30 seconds"
git push origin feature/update-health-monitor
```

### 4. Create Pull Request

1. Navigate to: Repos → Pull requests → New pull request
2. Source branch: `feature/update-health-monitor`
3. Target branch: `main`
4. Title: "Update health monitor collection interval"
5. Link to work item (create one if needed)
6. Click: Create

### 5. Watch Pipeline Run

- Build validation pipeline triggers automatically
- Navigate to Pipelines to watch progress
- Wait for green checkmark

### 6. Approve and Complete

1. Review the changes
2. Click: Approve
3. Click: Complete
4. Select: Merge (not squash)

### 7. Observe GitOps Deployment

After merge:
1. Pipeline builds new container image with incremented tag
2. Manifest updated with new image tag
3. Flux detects change within 5 minutes
4. Pod restarts with new image

### Verification Commands

```powershell
# On VM - watch pods restart
kubectl get pods -n ipc-workloads -w

# Check current image version
kubectl describe pod -n ipc-workloads -l app=health-monitor | Select-String "Image:"

# View pod logs to confirm new interval
kubectl logs -n ipc-workloads -l app=health-monitor --tail=5
```

---

## Pipeline Execution History

View past pipeline runs:

1. Navigate to: Pipelines → build-containers
2. Click on any run to see:
   - Which workloads were built
   - Build duration
   - Logs for each stage

### Artifacts

Each pipeline run produces artifacts:
- **packer-config**: Packer templates (golden image pipeline)
- Container images pushed to ACR with build ID tags

### Container Images in ACR

After successful builds, verify images in ACR:

```powershell
# List all IPC images
az acr repository list --name <your-acr-name> --output table

# Expected output (10 images):
# ipc/opcua-gateway
# ipc/health-monitor
# ipc/log-forwarder
# ipc/anomaly-detection
# ipc/test-data-collector
# ipc/opcua-simulator
# ipc/ev-battery-simulator
# ipc/vision-simulator
# ipc/motion-simulator
# ipc/motion-gateway

# Check tags for a specific image
az acr repository show-tags --name <your-acr-name> --repository ipc/ev-battery-simulator --output table
```

---

## Troubleshooting

### Pipeline Fails: "Service Connection Not Found"

**Symptom:** `azure-subscription` service connection not found

**Fix:**
1. Navigate to: Project Settings → Service connections
2. Verify `azure-subscription` exists
3. If missing, create new Azure Resource Manager connection with Workload Identity Federation

### Pipeline Fails: ACR Access Denied

**Symptom:** `az acr build` fails with 401 Unauthorized

**Fix:**
1. Verify service connection has Contributor role on ACR
2. Check: `az role assignment list --scope /subscriptions/.../resourceGroups/rg-ipc-platform-acr/providers/Microsoft.ContainerRegistry/registries/<your-acr-name>`

### Build Not Triggered

**Symptom:** Changes pushed but pipeline doesn't run

**Check triggers:**
- Verify changes are in correct path (`docker/**` or `packer/**`)
- Verify push is to `main` branch (for CI) or PR targeting `main` (for PR validation)
- Check pipeline is not paused: Pipelines → ⋮ → Settings

### Specific Workload Not Building

**Symptom:** Changed a workload but pipeline didn't trigger

**Check:**
1. Verify the `azure-pipelines.yml` trigger path includes the changed files.
2. Check that the pipeline file itself is valid (no syntax errors).
3. Ensure you haven't exceeded Azure DevOps parallel job limits.

### Flux Not Detecting Changes

**Symptom:** New image pushed but pods not updated

**Verify GitOps sync:**
```powershell
# On VM
kubectl get gitrepository -n flux-system
kubectl get kustomization -n flux-system
```

**Force sync:**
```powershell
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

---

## Demo Talking Points (Pillar 3)

When presenting Zero-Touch Updates:

- "Watch this—I'm going to change a configuration in our Git repository"
- "The PR triggers our build pipeline automatically for validation"
- "Once approved and merged, the pipeline builds a new container image"
- "Flux, running on the edge device, detects the new image"
- "Within 5 minutes, every connected IPC updates automatically"
- "No truck roll. No remote desktop. No manual intervention."
- "Full audit trail of who changed what, when, and why"

### Pipeline Stages Explanation

For a technical audience:

- "We use a dedicated pipeline for every workload (Golden Pipeline pattern)"
- "This isolates failures—if the simulated battery breaks, it doesn't stop the factory gateway"
- "Security is baked in: We scan for CVEs and cryptographically sign every image"
- "The physical device (IPC) uses Flux to verify that signature before running the code"

---

## Related Pages

- [GitOps Configuration](04-GitOps-Configuration.md) — Flux setup for automatic deployment
- [Azure Foundation](01-Azure-Foundation.md) — Service connection and variable group
- [Golden Image Pipeline](02-Golden-Image-Pipeline.md) — Packer template details
- [DevOps Operations Center](10-DevOps-Operations-Center.md) — Work item tracking
- [OPC-UA Workloads](05-Workloads-OPC-UA.md) — Simulator source code and documentation
