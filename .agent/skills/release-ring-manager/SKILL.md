---
name: release-ring-manager
description: |
  Use this skill to manage CI/CD pipelines and deployment promotion.
  Activated when: pipelines need creation or modification, build failures
  need investigation, or deployments need promotion between rings.
  The gatekeeper of releases.
license: MIT
metadata:
  author: <your-org>
  version: "1.0"
  area: Operations
  pillar: Deploy
---

# Release Ring Manager

## Role

Manages the CI/CD pipeline lifecycle and deployment promotion strategy. Controls how code moves from development through validation to production via GitOps. Ensures builds are validated, images are pushed to registry, and Flux deploys changes safely.

## Trigger Conditions

- Pipeline creation or modification requested
- Build failure needs investigation
- `fleet-conductor` routes CI/CD work
- Request contains: "pipeline", "build", "deploy", "release", "promote", "ci/cd"
- Changes to `pipelines/`, `.azure-pipelines/`
- Branch policy configuration needed
- Deployment promotion between rings (Dev → Alpha → Beta → Production)
- GitOps sync issues related to image updates

## Inputs

- Pipeline requirements or issue description
- Build failure logs
- Target environment for promotion
- Image tags to deploy

## Outputs

- Pipeline YAML definitions
- Build investigation findings
- Promotion approvals/rejections
- Deployment status reports

---

## Phase 1: Pipeline Assessment

When pipeline work is triggered:

1. **Identify the pipeline context**:

   | Pipeline | Trigger | Purpose |
   |----------|---------|---------|
   | `build-containers.yml` | `docker/**` changes | Build and push container images |
   | `build-golden-image.yml` | `packer/**` changes | Validate Packer templates |
   | `validate-manifests.yml` | `kubernetes/**` changes | Lint K8s manifests |
   | `compliance-scan.yml` | Scheduled/manual | Security scanning |

2. **Assess current state**:
   ```powershell
   # Check recent pipeline runs (Azure DevOps CLI)
   az pipelines runs list --top 10 --query "[].{ID:id,Pipeline:definition.name,Status:status,Result:result}"
   ```

3. **Determine work type**:
   - **Creating new pipeline** → Phase 2A
   - **Modifying existing pipeline** → Phase 2B
   - **Investigating failure** → Phase 2C
   - **Promoting deployment** → Phase 2D

4. **REPORT** assessment:
   ```
   PIPELINE ASSESSMENT
   ===================
   Request: [description]
   Work Type: [Create/Modify/Investigate/Promote]
   
   Current State:
   - Pipeline: [name or N/A]
   - Last Run: [status]
   - Last Success: [date]
   
   Affected Components:
   - [component list]
   
   Proceed with [work type]? [Y/N]
   ```

## Phase 2A: Creating New Pipeline

1. **Gather requirements**:
   - What triggers the pipeline?
   - What steps are needed?
   - What artifacts are produced?
   - What validations are required?

2. **Design pipeline structure**:
   ```yaml
   # Standard pipeline structure
   trigger:
     branches:
       include: [main]
     paths:
       include: [relevant/paths/**]
   
   pool:
     vmImage: 'ubuntu-latest'
   
   variables:
     - group: ipc-platform-variables
   
   stages:
     - stage: Build
       jobs:
         - job: BuildJob
           steps:
             - task: ...
     
     - stage: Validate
       dependsOn: Build
       jobs:
         - job: ValidateJob
           steps:
             - task: ...
     
     - stage: Publish
       dependsOn: Validate
       condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
       jobs:
         - job: PublishJob
           steps:
             - task: ...
   ```

3. **PAUSE** and present pipeline design.

4. **WAIT** for approval before creating.

## Phase 2B: Modifying Existing Pipeline

1. **Understand current pipeline**:
   ```powershell
   # View pipeline definition
   az pipelines show --name "build-containers"
   ```

2. **Identify change scope**:
   - Trigger changes
   - Step modifications
   - Variable updates
   - Stage additions

3. **Plan modifications**:
   ```
   PIPELINE MODIFICATION PLAN
   ==========================
   Pipeline: [name]
   
   Current State:
   - [relevant current config]
   
   Proposed Changes:
   1. [change 1]
   2. [change 2]
   
   Impact:
   - [what will be affected]
   
   Rollback:
   - [how to undo if needed]
   ```

4. **PAUSE** and present plan.

## Phase 2C: Investigating Build Failure

1. **Gather failure information**:
   ```powershell
   # Get failed run details
   az pipelines runs show --id <run-id>
   
   # Get logs
   az pipelines runs logs show --id <run-id>
   ```

2. **Classify failure type**:

   | Failure Type | Indicators | Resolution Path |
   |--------------|------------|-----------------|
   | Authentication | 401, 403, "access denied" | `secret-rotation-manager` |
   | Build error | Compilation, syntax errors | `platform-engineer` |
   | ACR push fail | "unauthorized", registry errors | Check ACR config |
   | Validation fail | Test failures, lint errors | Fix code issues |
   | Timeout | "exceeded time limit" | Optimize or increase |
   | Infrastructure | Agent issues, capacity | Azure DevOps support |

3. **REPORT** investigation findings:
   ```
   BUILD FAILURE INVESTIGATION
   ===========================
   Pipeline: [name]
   Run ID: [id]
   Failed At: [timestamp]
   
   Failure Type: [classification]
   
   Error Details:
   ```
   [error message]
   ```
   
   Root Cause:
   [analysis]
   
   Resolution:
   - [steps to fix]
   
   Route To: [skill or action]
   ```

## Phase 2D: Deployment Promotion

1. **Verify promotion readiness**:
   ```
   PROMOTION CHECKLIST
   ===================
   Image: [registry/image:tag]
   
   Source Environment: [current]
   Target Environment: [destination]
   
   Prerequisites:
   - [ ] Build succeeded
   - [ ] Tests passed
   - [ ] Security scan clean
   - [ ] Compliance approved
   - [ ] Previous ring stable
   ```

2. **Promotion workflow**:
   ```
   Dev → Alpha → Beta → Production
   
   Dev:    Every commit to main
   Alpha:  Manual promotion, internal testing
   Beta:   Manual promotion, limited customers
   Prod:   Manual promotion, full rollout
   ```

3. **Execute promotion** (GitOps):
   ```powershell
   # Update manifest with new image tag
   # File: kubernetes/overlays/[environment]/kustomization.yaml
   
   images:
     - name: <your-acr-name>.azurecr.io/dmc/[workload]
       newTag: "[new-tag]"
   ```

4. **PAUSE** for promotion approval.

## Phase 3: Execution

Upon approval:

### For Pipeline Creation/Modification

1. **Create/update pipeline file**:
   ```powershell
   # Validate YAML syntax
   az pipelines validate --yaml-path pipelines/new-pipeline.yml
   ```

2. **Create pipeline in Azure DevOps**:
   ```powershell
   az pipelines create `
     --name "pipeline-name" `
     --yaml-path "pipelines/pipeline-name.yml" `
     --repository IPC-Platform-Engineering `
     --repository-type tfsgit `
     --branch main
   ```

3. **Configure branch policies** (if needed):
   ```powershell
   az repos policy build create `
     --repository-id <repo-id> `
     --branch main `
     --build-definition-id <pipeline-id> `
     --enabled true `
     --blocking true `
     --display-name "Build Validation"
   ```

### For Build Failure

1. **Route to appropriate skill** based on failure type
2. **Track resolution progress**
3. **Verify fix with new build run**

### For Promotion

1. **Update environment manifests**
2. **Commit changes to Git**
3. **Monitor Flux sync**
4. **Verify deployment health**

## Phase 4: Verification

After execution:

1. **Verify pipeline operation**:
   ```powershell
   # Trigger test run
   az pipelines run --name "pipeline-name"
   
   # Monitor status
   az pipelines runs show --id <run-id>
   ```

2. **Verify deployment** (for promotions):
   ```powershell
   # Check Flux sync
   kubectl get kustomizations -n flux-system
   
   # Check pods
   kubectl get pods -n dmc-workloads
   ```

3. **REPORT** completion:
   ```
   PIPELINE OPERATION COMPLETE
   ===========================
   Operation: [create/modify/fix/promote]
   
   Result: SUCCESS
   
   Verification:
   - [x] Pipeline runs successfully
   - [x] Artifacts produced correctly
   - [x] Deployment healthy (if applicable)
   
   Next Actions:
   - [any follow-up needed]
   ```

---

## Pipeline Patterns

### Container Build Template

```yaml
parameters:
  - name: imageName
    type: string
  - name: dockerfilePath
    type: string
    default: 'Dockerfile'

steps:
  - task: Docker@2
    displayName: 'Build ${{ parameters.imageName }}'
    inputs:
      command: build
      repository: dmc/${{ parameters.imageName }}
      dockerfile: ${{ parameters.dockerfilePath }}
      tags: |
        $(Build.BuildId)
        latest

  - task: Docker@2
    displayName: 'Push ${{ parameters.imageName }}'
    inputs:
      command: push
      containerRegistry: 'acr-service-connection'
      repository: dmc/${{ parameters.imageName }}
      tags: |
        $(Build.BuildId)
        latest
```

### Path-Based Triggers

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - docker/health-monitor/**
    exclude:
      - '**/*.md'
```

---

## Tool Access

| Tool | Purpose |
|------|---------|
| `az pipelines` | Pipeline management |
| `az repos` | Branch policies |
| `kubectl` | Deployment verification |
| `flux` | GitOps status |
| Git | Manifest updates |

## Handoff Rules

| Situation | Action |
|-----------|--------|
| Authentication failure | Route to `secret-rotation-manager` |
| Code/build error | Route to `platform-engineer` |
| GitOps sync issue | Route to `drift-detection-analyst` |
| Deployment unhealthy | Route to `site-reliability-engineer` |
| Compliance gate failed | Route to `compliance-auditor` |

## Constraints

- **Never skip validation stages** — All builds must be validated
- **Never promote without approval** — Manual gates required
- **Never bypass branch policies** — Policies exist for safety
- **Always verify after changes** — Test pipeline modifications
- **Always document promotions** — Audit trail required
- **Rollback on failure** — Don't leave broken deployments
