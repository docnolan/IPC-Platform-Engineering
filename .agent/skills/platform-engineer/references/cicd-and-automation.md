# CI/CD and Automation Frameworks

Comprehensive guide for CI/CD pipelines, Infrastructure-as-Code templates, and reusable automation frameworks for edge platform engineering.

## CI/CD Tool Comparison

### Pipeline Platforms

| Tool | Type | Best For | Self-Hosted | K8s Native |
|------|------|----------|-------------|------------|
| **Azure DevOps** | Full platform | Azure ecosystem | Yes (Server) | No |
| **GitHub Actions** | Cloud-native | GitHub repos | Yes (runners) | No |
| **GitLab CI** | Full platform | GitLab repos | Yes | No |
| **Jenkins** | Self-hosted | Custom workflows | Yes | Optional |
| **Tekton** | K8s-native | Cloud-native CI | Yes | Yes |
| **Argo Workflows** | K8s-native | Complex workflows | Yes | Yes |

### GitOps Tools

| Tool | Vendor | Model | Best For |
|------|--------|-------|----------|
| **Flux** | CNCF | Pull-based | Kubernetes-first |
| **ArgoCD** | CNCF | Pull-based | Multi-cluster, UI |
| **Jenkins X** | Jenkins | Push/Pull | Jenkins users |
| **Rancher Fleet** | SUSE | Pull-based | Rancher ecosystem |

---

## Azure DevOps Pipelines

### Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Azure DevOps Pipeline                     │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                     Trigger                          │   │
│  │  • CI: Push to branch                                │   │
│  │  • PR: Pull request validation                       │   │
│  │  • Schedule: Cron expression                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   Stage: Build                       │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │  Checkout   │→ │   Build     │→ │    Test     │  │   │
│  │  │   Code      │  │  Container  │  │   (Unit)    │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  Stage: Publish                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │   Scan      │→ │    Push     │→ │   Update    │  │   │
│  │  │  (Trivy)    │  │   to ACR    │  │  Manifest   │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  GitOps Deployment                   │   │
│  │         (Flux detects manifest change)               │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Pipeline Template: Container Build

```yaml
# templates/container-build.yml
parameters:
  - name: imageName
    type: string
  - name: dockerfilePath
    type: string
    default: 'Dockerfile'
  - name: buildContext
    type: string
    default: '.'
  - name: acrServiceConnection
    type: string
    default: 'acr-service-connection'

steps:
  - task: Docker@2
    displayName: 'Build container image'
    inputs:
      command: build
      repository: ${{ parameters.imageName }}
      dockerfile: ${{ parameters.dockerfilePath }}
      buildContext: ${{ parameters.buildContext }}
      tags: |
        $(Build.BuildId)
        $(Build.SourceVersion)
        latest

  - task: Docker@2
    displayName: 'Push to ACR'
    inputs:
      command: push
      containerRegistry: ${{ parameters.acrServiceConnection }}
      repository: ${{ parameters.imageName }}
      tags: |
        $(Build.BuildId)
        $(Build.SourceVersion)
        latest
```

### Pipeline Template: Multi-Container Build

```yaml
# pipelines/build-containers.yml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - docker/**

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: ipc-platform-variables
  - name: acrLoginServer
    value: $(ACR_LOGIN_SERVER)

stages:
  - stage: Build
    displayName: 'Build Containers'
    jobs:
      - job: DetectChanges
        displayName: 'Detect Changed Workloads'
        steps:
          - bash: |
              # Detect which workloads changed
              changed=$(git diff --name-only HEAD~1 HEAD -- docker/)
              workloads=""
              for dir in docker/*/; do
                name=$(basename $dir)
                if echo "$changed" | grep -q "docker/$name/"; then
                  workloads="$workloads $name"
                fi
              done
              echo "##vso[task.setvariable variable=changedWorkloads;isOutput=true]$workloads"
            name: detect
            displayName: 'Detect changed workloads'

      - job: BuildWorkloads
        displayName: 'Build Changed Workloads'
        dependsOn: DetectChanges
        variables:
          workloads: $[ dependencies.DetectChanges.outputs['detect.changedWorkloads'] ]
        strategy:
          matrix:
            health-monitor:
              workloadName: 'health-monitor'
            log-forwarder:
              workloadName: 'log-forwarder'
            opcua-simulator:
              workloadName: 'opcua-simulator'
            opcua-gateway:
              workloadName: 'opcua-gateway'
            anomaly-detection:
              workloadName: 'anomaly-detection'
            test-data-collector:
              workloadName: 'test-data-collector'
        steps:
          - task: Docker@2
            displayName: 'Login to ACR'
            inputs:
              command: login
              containerRegistry: 'acr-service-connection'

          - bash: |
              if echo "$(workloads)" | grep -q "$(workloadName)"; then
                echo "Building $(workloadName)..."
                docker build -t $(acrLoginServer)/dmc/$(workloadName):$(Build.BuildId) \
                  -t $(acrLoginServer)/dmc/$(workloadName):latest \
                  docker/$(workloadName)/
                docker push $(acrLoginServer)/dmc/$(workloadName):$(Build.BuildId)
                docker push $(acrLoginServer)/dmc/$(workloadName):latest
              else
                echo "$(workloadName) not changed, skipping..."
              fi
            displayName: 'Build and push $(workloadName)'
```

### Variable Groups

```yaml
# Variable group: ipc-platform-variables
variables:
  - name: ACR_LOGIN_SERVER
    value: <your-acr-name>.azurecr.io
  - name: AZURE_SUBSCRIPTION_ID
    value: <your-subscription-id>
  - name: LOG_ANALYTICS_WORKSPACE_ID
    value: <your-workspace-id>
  - name: IOT_HUB_NAME
    value: <your-iothub-name>
```

---

## GitHub Actions

### Workflow: Container Build

```yaml
# .github/workflows/build-containers.yml
name: Build Containers

on:
  push:
    branches: [main]
    paths:
      - 'docker/**'
  pull_request:
    branches: [main]
    paths:
      - 'docker/**'

env:
  REGISTRY: ghcr.io
  IMAGE_PREFIX: ${{ github.repository }}

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - id: set-matrix
        run: |
          changed=$(git diff --name-only HEAD~1 HEAD -- docker/ | cut -d'/' -f2 | sort -u)
          matrix=$(echo "$changed" | jq -R -s -c 'split("\n") | map(select(length > 0))')
          echo "matrix={\"workload\":$matrix}" >> $GITHUB_OUTPUT

  build:
    needs: detect-changes
    if: ${{ needs.detect-changes.outputs.matrix != '{"workload":[]}' }}
    runs-on: ubuntu-latest
    strategy:
      matrix: ${{ fromJson(needs.detect-changes.outputs.matrix) }}
    
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Log in to registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: docker/${{ matrix.workload }}
          push: ${{ github.event_name != 'pull_request' }}
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_PREFIX }}/${{ matrix.workload }}:${{ github.sha }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_PREFIX }}/${{ matrix.workload }}:latest
```

---

## GitOps with Flux

### Flux Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Git Repository                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  kubernetes/                                         │   │
│  │  ├── base/                                          │   │
│  │  ├── overlays/                                      │   │
│  │  │   ├── dev/                                       │   │
│  │  │   ├── staging/                                   │   │
│  │  │   └── production/                                │   │
│  │  └── workloads/                                     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ (Flux watches)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 flux-system namespace                │   │
│  │  ┌────────────────┐  ┌────────────────┐             │   │
│  │  │ source-        │  │ kustomize-     │             │   │
│  │  │ controller     │  │ controller     │             │   │
│  │  │                │  │                │             │   │
│  │  │ (Fetches Git)  │  │ (Applies YAML) │             │   │
│  │  └────────────────┘  └────────────────┘             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                dmc-workloads namespace               │   │
│  │  (Workloads deployed by Flux)                        │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Flux Bootstrap

```bash
# Install Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Bootstrap with Azure DevOps
flux bootstrap git \
  --url=https://dev.azure.com/org/project/_git/repo \
  --branch=main \
  --path=kubernetes/clusters/edge-01 \
  --token-auth

# Or with GitHub
flux bootstrap github \
  --owner=myorg \
  --repository=ipc-platform \
  --branch=main \
  --path=kubernetes/clusters/edge-01 \
  --personal
```

### GitRepository Source

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: ipc-platform-config
  namespace: flux-system
spec:
  interval: 5m
  url: https://dev.azure.com/<your-org>/IPC-Platform-Engineering/_git/IPC-Platform-Engineering
  ref:
    branch: main
  secretRef:
    name: flux-git-credentials
```

### Kustomization

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: workloads
  namespace: flux-system
spec:
  interval: 5m
  path: ./kubernetes/workloads
  prune: true
  sourceRef:
    kind: GitRepository
    name: ipc-platform-config
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: health-monitor
      namespace: dmc-workloads
```

---

## Reusable Automation Frameworks

### PowerShell Module Structure

```
IPC-Platform-Automation/
├── IPC-Platform-Automation.psd1    # Module manifest
├── IPC-Platform-Automation.psm1    # Module loader
├── Public/                          # Exported functions
│   ├── Deploy-IPCWorkload.ps1
│   ├── Get-IPCHealth.ps1
│   ├── New-IPCEnvironment.ps1
│   └── Update-IPCConfiguration.ps1
├── Private/                         # Internal functions
│   ├── Connect-IPCAzure.ps1
│   ├── Get-IPCConfiguration.ps1
│   └── Write-IPCLog.ps1
└── Tests/                          # Pester tests
    ├── Deploy-IPCWorkload.Tests.ps1
    └── Get-IPCHealth.Tests.ps1
```

### Module Manifest

```powershell
# IPC-Platform-Automation.psd1
@{
    RootModule = 'IPC-Platform-Automation.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Platform Team'
    Description = 'Automation framework for IPC Platform edge deployments'
    
    PowerShellVersion = '7.0'
    
    RequiredModules = @(
        'Az.Accounts',
        'Az.Resources',
        'Az.ContainerRegistry'
    )
    
    FunctionsToExport = @(
        'Deploy-IPCWorkload',
        'Get-IPCHealth',
        'New-IPCEnvironment',
        'Update-IPCConfiguration'
    )
    
    PrivateData = @{
        PSData = @{
            Tags = @('IPC', 'Platform', 'Edge', 'Automation')
            ProjectUri = 'https://dev.azure.com/org/IPC-Platform'
        }
    }
}
```

### Reusable Deployment Function

```powershell
# Public/Deploy-IPCWorkload.ps1
function Deploy-IPCWorkload {
    <#
    .SYNOPSIS
        Deploys an IPC Platform workload to the edge cluster.
    
    .DESCRIPTION
        Handles the complete deployment workflow including image
        verification, manifest generation, and GitOps commit.
    
    .PARAMETER WorkloadName
        Name of the workload to deploy.
    
    .PARAMETER ImageTag
        Container image tag to deploy.
    
    .PARAMETER Environment
        Target environment (dev, staging, production).
    
    .EXAMPLE
        Deploy-IPCWorkload -WorkloadName "health-monitor" -ImageTag "1.0.0"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("health-monitor", "log-forwarder", "opcua-simulator", 
                     "opcua-gateway", "anomaly-detection", "test-data-collector")]
        [string]$WorkloadName,
        
        [Parameter(Mandatory)]
        [string]$ImageTag,
        
        [Parameter()]
        [ValidateSet("dev", "staging", "production")]
        [string]$Environment = "dev",
        
        [Parameter()]
        [switch]$SkipImageVerification
    )
    
    begin {
        Write-IPCLog -Message "Starting deployment: $WorkloadName ($ImageTag)" -Level Info
        
        # Verify Azure connection
        $context = Get-AzContext
        if (-not $context) {
            throw "Not connected to Azure. Run Connect-AzAccount first."
        }
    }
    
    process {
        # Step 1: Verify image exists in ACR
        if (-not $SkipImageVerification) {
            Write-IPCLog -Message "Verifying image in ACR..." -Level Verbose
            $config = Get-IPCConfiguration
            $imageExists = az acr repository show-tags `
                --name $config.AcrName `
                --repository "dmc/$WorkloadName" `
                --query "contains(@, '$ImageTag')" `
                --output tsv
            
            if ($imageExists -ne "true") {
                throw "Image dmc/${WorkloadName}:${ImageTag} not found in ACR"
            }
        }
        
        # Step 2: Update manifest
        $manifestPath = "kubernetes/workloads/$WorkloadName/deployment.yaml"
        if ($PSCmdlet.ShouldProcess($manifestPath, "Update image tag")) {
            Write-IPCLog -Message "Updating manifest: $manifestPath" -Level Info
            
            $manifest = Get-Content $manifestPath -Raw
            $newImage = "$($config.AcrLoginServer)/dmc/${WorkloadName}:${ImageTag}"
            $manifest = $manifest -replace "image: .*/dmc/${WorkloadName}:.*", "image: $newImage"
            Set-Content -Path $manifestPath -Value $manifest
        }
        
        # Step 3: Commit and push (GitOps)
        if ($PSCmdlet.ShouldProcess("Git repository", "Commit deployment")) {
            Write-IPCLog -Message "Committing to Git..." -Level Info
            
            git add $manifestPath
            git commit -m "deploy($WorkloadName): Update to $ImageTag"
            git push
        }
        
        # Step 4: Wait for Flux sync (optional)
        Write-IPCLog -Message "Deployment committed. Flux will sync within 5 minutes." -Level Info
        Write-IPCLog -Message "Run 'kubectl get kustomizations -n flux-system' to check status." -Level Info
    }
    
    end {
        Write-IPCLog -Message "Deployment complete: $WorkloadName ($ImageTag)" -Level Info
    }
}
```

---

## Terraform Patterns

### Module Structure

```
terraform/
├── modules/
│   ├── azure-foundation/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── iot-hub/
│   ├── log-analytics/
│   └── container-registry/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── staging/
│   └── production/
└── shared/
    └── versions.tf
```

### Reusable Module Example

```hcl
# modules/azure-foundation/main.tf

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralus"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

locals {
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30
  tags                = local.common_tags
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "resource_group_id" {
  value = azurerm_resource_group.main.id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.workspace_id
}
```

### Environment Configuration

```hcl
# environments/dev/main.tf

module "foundation" {
  source = "../../modules/azure-foundation"
  
  project_name = "ipc-platform"
  environment  = "dev"
  location     = "centralus"
  
  tags = {
    CostCenter = "Engineering"
    Owner      = "platform-team"
  }
}

module "iot_hub" {
  source = "../../modules/iot-hub"
  
  resource_group_name = module.foundation.resource_group_name
  location           = "centralus"
  environment        = "dev"
}
```

---

## Self-Service Patterns

### Template Repository

Provide teams with standardized starting points:

```
ipc-workload-template/
├── .github/
│   └── workflows/
│       └── build.yml           # Pre-configured CI
├── docker/
│   └── Dockerfile.template     # Base Dockerfile
├── kubernetes/
│   ├── deployment.yaml.template
│   └── kustomization.yaml
├── src/
│   └── main.py.template        # Starter code
├── tests/
│   └── test_main.py
├── README.md
└── cookiecutter.json           # Template variables
```

### Cookiecutter Template

```json
// cookiecutter.json
{
    "workload_name": "my-workload",
    "description": "A new IPC Platform workload",
    "author": "Platform Team",
    "python_version": "3.11",
    "include_opcua": false,
    "include_azure_sdk": true,
    "log_analytics_table": "Custom_CL"
}
```

### Onboarding Script

```powershell
# New-IPCWorkload.ps1
function New-IPCWorkload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkloadName,
        
        [Parameter()]
        [switch]$IncludeOpcUA,
        
        [Parameter()]
        [switch]$IncludeAzureSDK
    )
    
    # Clone template
    git clone https://dev.azure.com/org/templates/_git/ipc-workload-template `
        "docker/$WorkloadName"
    
    # Replace placeholders
    Get-ChildItem "docker/$WorkloadName" -Recurse -File | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $content = $content -replace '{{WORKLOAD_NAME}}', $WorkloadName
        $content = $content -replace '{{INCLUDE_OPCUA}}', $IncludeOpcUA.ToString()
        Set-Content $_.FullName $content
    }
    
    # Create Kubernetes manifests
    New-Item -ItemType Directory -Path "kubernetes/workloads/$WorkloadName"
    # ... generate manifests
    
    Write-Host "Workload $WorkloadName created successfully!"
    Write-Host "Next steps:"
    Write-Host "  1. Implement your workload in docker/$WorkloadName/src/"
    Write-Host "  2. Run 'git add .' and commit"
    Write-Host "  3. Push to trigger CI/CD pipeline"
}
```

---

## IPC Platform CI/CD Summary

| Component | Tool | Trigger | Output |
|-----------|------|---------|--------|
| Container builds | Azure DevOps | Push to `docker/**` | ACR images |
| Image manifests | Azure DevOps | Post-build | Updated YAML |
| Deployment | Flux | Git commit | K8s resources |
| Validation | Flux | Post-deploy | Health checks |
| Rollback | Git revert | Manual | Previous state |
