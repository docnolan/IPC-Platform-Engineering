# Pipeline Patterns

Reference document for Azure DevOps pipeline conventions and patterns used in the IPC Platform.

## Pipeline Inventory

| Pipeline | File | Trigger | Purpose |
|----------|------|---------|---------|
| build-containers | `pipelines/build-containers.yml` | `docker/**` | Build and push container images to ACR |
| build-golden-image | `pipelines/build-golden-image.yml` | `packer/**` | Validate Packer templates |

## Directory Structure

```
C:\Projects\IPC-Platform-Engineering\
└── pipelines\
    ├── build-containers.yml      # Main container build pipeline
    ├── build-golden-image.yml    # Packer validation pipeline
    └── templates\
        └── build-container.yml   # Reusable template for single container
```

## Variable Group

**Name:** `ipc-platform-variables`

| Variable | Description | Example |
|----------|-------------|---------|
| `azureSubscriptionId` | Azure subscription | `<your-subscription-id>` |
| `azureTenantId` | Azure AD tenant | `<your-tenant-id>` |
| `location` | Azure region | `centralus` |
| `acrName` | Container registry name | `<your-acr-name>` |
| `iotHubName` | IoT Hub name | `<your-iothub-name>` |
| `logAnalyticsWorkspaceId` | Log Analytics ID | `<your-workspace-id>` |
| `arcClusterName` | Arc cluster name | `<your-arc-cluster-name>` |
| `arcResourceGroup` | Arc resource group | `rg-ipc-platform-arc` |

## Pipeline Templates

### Container Build Template

**File:** `pipelines/templates/build-container.yml`

```yaml
parameters:
  - name: workloadName
    type: string
  - name: dockerfilePath
    type: string
  - name: contextPath
    type: string

steps:
  - task: AzureCLI@2
    displayName: 'Build and Push ${{ parameters.workloadName }}'
    inputs:
      azureSubscription: 'azure-subscription'
      scriptType: 'bash'
      scriptLocation: 'inlineScript'
      inlineScript: |
        az acr build \
          --registry $(acrName) \
          --image dmc/${{ parameters.workloadName }}:$(imageTag) \
          --image dmc/${{ parameters.workloadName }}:latest \
          --file ${{ parameters.dockerfilePath }} \
          ${{ parameters.contextPath }}
```

### Usage Pattern

```yaml
- template: templates/build-container.yml
  parameters:
    workloadName: 'health-monitor'
    dockerfilePath: 'docker/health-monitor/Dockerfile'
    contextPath: 'docker/health-monitor'
```

## Trigger Patterns

### Path-Based CI Triggers

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - docker/**        # Any change in docker/ triggers build
```

### PR Validation Triggers

```yaml
pr:
  branches:
    include:
      - main
  paths:
    include:
      - docker/**        # Validate PRs touching docker/
```

### Change Detection Pattern

Detect which workloads changed to build only affected containers:

```yaml
- task: PowerShell@2
  name: detectChanges
  displayName: 'Detect Changed Workloads'
  inputs:
    targetType: 'inline'
    script: |
      $changedFiles = git diff --name-only HEAD~1 HEAD
      $workloads = @("opcua-simulator", "opcua-gateway", "health-monitor", 
                     "log-forwarder", "anomaly-detection", "test-data-collector")
      
      $changedWorkloads = @()
      foreach ($workload in $workloads) {
        if ($changedFiles | Where-Object { $_ -like "docker/$workload/*" }) {
          $changedWorkloads += $workload
        }
      }
      
      $workloadList = $changedWorkloads -join ','
      Write-Host "##vso[task.setvariable variable=changedWorkloads;isOutput=true]$workloadList"
```

## Stage Patterns

### Standard Multi-Stage Pipeline

```yaml
stages:
  - stage: Validate
    displayName: 'Validate'
    jobs:
      - job: ValidateSyntax
        steps:
          # Syntax validation steps

  - stage: Build
    displayName: 'Build'
    dependsOn: Validate
    condition: succeeded()
    jobs:
      - job: BuildImages
        steps:
          # Build steps

  - stage: Deploy
    displayName: 'Deploy to Dev'
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - job: UpdateManifests
        steps:
          # Update kubernetes manifests
```

### Conditional Stage Execution

```yaml
# Only run on main branch merges
condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))

# Only run if changes detected
condition: eq(dependencies.Detect.outputs['detectChanges.hasChanges'], 'True')

# Only run specific job if workload changed
condition: contains(dependencies.Detect.outputs['detectChanges.changedWorkloads'], 'health-monitor')
```

## Image Tagging Strategy

| Tag | Purpose | When Applied |
|-----|---------|--------------|
| `latest` | Most recent build | Every successful build |
| `$(Build.BuildId)` | Unique build identifier | Every build |
| `$(Build.SourceVersion)` | Git commit SHA | Every build |
| `v1.0.0` | Semantic version | Release tags |

### Recommended Tagging

```yaml
variables:
  imageTag: '$(Build.BuildId)'

# Apply both specific and latest tags
az acr build \
  --image dmc/workload:$(imageTag) \
  --image dmc/workload:latest \
  ...
```

## Branch Policies

### Main Branch Protection

Configure in Azure DevOps → Repos → Branches → main → Branch policies:

| Policy | Setting |
|--------|---------|
| Require minimum reviewers | 1 reviewer |
| Check for linked work items | Optional |
| Check for comment resolution | Required |
| Build validation | `build-containers` pipeline |
| Automatically include reviewers | Optional |

### PR Build Validation

```yaml
# In pipeline definition
pr:
  branches:
    include:
      - main
  paths:
    include:
      - docker/**
      - kubernetes/**
```

## Deployment Flow

### GitOps Deployment Pattern

```
Developer → PR → Build Validation → Merge → CI Build → ACR Push
                                                          ↓
                                              Update kubernetes/ manifest
                                                          ↓
                                              Git push (triggers Flux)
                                                          ↓
                                              Flux detects change
                                                          ↓
                                              Pods updated on cluster
```

### Manual Manifest Update (Post-Build)

```yaml
- task: PowerShell@2
  displayName: 'Update Kubernetes Manifest'
  inputs:
    targetType: 'inline'
    script: |
      $manifestPath = "kubernetes/workloads/${{ parameters.workloadName }}/deployment.yaml"
      $content = Get-Content $manifestPath -Raw
      $content = $content -replace "image:.*${{ parameters.workloadName }}:.*", `
                                   "image: $(acrLoginServer)/dmc/${{ parameters.workloadName }}:$(imageTag)"
      $content | Set-Content $manifestPath
```

## Troubleshooting

### Common Pipeline Failures

| Error | Cause | Resolution |
|-------|-------|------------|
| `az acr build` 401 Unauthorized | Service connection expired | Refresh service connection |
| `No subscription found` | Not logged in to Azure | Check service connection |
| `Dockerfile not found` | Wrong context path | Verify `contextPath` parameter |
| `Image push failed` | ACR quota or permissions | Check ACR settings |
| `Variable not found` | Missing variable group link | Add variable group to pipeline |

### Service Connection Verification

```powershell
# List service connections
az devops service-endpoint list --project "IPC-Platform-Engineering"

# Test Azure CLI authentication
az account show
az acr list --query "[].name"
```

### Pipeline Run Investigation

```powershell
# List recent runs
az pipelines runs list --project "IPC-Platform-Engineering" --top 10

# Get specific run details
az pipelines runs show --id <run-id> --project "IPC-Platform-Engineering"

# Get logs (requires web UI or REST API)
# Navigate to: Azure DevOps → Pipelines → Runs → Select Run → Logs
```

## Security Considerations

1. **Never hardcode secrets** — Use variable groups marked as secret
2. **Use service connections** — Not personal credentials
3. **Limit pipeline scope** — Only access required resources
4. **Audit pipeline changes** — All YAML changes go through PR
5. **Validate inputs** — Sanitize any dynamic inputs in scripts
