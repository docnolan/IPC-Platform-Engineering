# GitOps Operations Reference

Reference document for Flux GitOps operations, troubleshooting, and drift remediation procedures.

## Flux Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUX SYSTEM                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │ source-         │───▶│ kustomize-      │───▶│ Kubernetes      │ │
│  │ controller      │    │ controller      │    │ API Server      │ │
│  │                 │    │                 │    │                 │ │
│  │ Fetches Git     │    │ Applies         │    │ Creates/Updates │ │
│  │ repository      │    │ manifests       │    │ resources       │ │
│  └────────┬────────┘    └─────────────────┘    └─────────────────┘ │
│           │                                                         │
│           ▼                                                         │
│  ┌─────────────────┐                                               │
│  │ GitRepository   │  Azure DevOps Repo                            │
│  │ (CRD)           │◀─────────────────────                         │
│  └─────────────────┘                                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Flux Custom Resources

### GitRepository

Defines the Git source to watch:

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

Defines what to deploy from the Git source:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ipc-platform-config-workloads
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: ipc-platform-config
  path: ./kubernetes/workloads
  prune: true
  targetNamespace: dmc-workloads
```

## Status Interpretation

### GitRepository Status

| Condition | Meaning | Action |
|-----------|---------|--------|
| `Ready: True` | Git repo fetched successfully | None |
| `Ready: False` + `authentication` | Credential issue | Rotate PAT |
| `Ready: False` + `clone` | Network/URL issue | Check connectivity |
| `Ready: False` + `timeout` | Slow network | Increase timeout or retry |
| `Stalled` | Cannot make progress | Manual investigation |

### Kustomization Status

| Condition | Meaning | Action |
|-----------|---------|--------|
| `Ready: True` | All resources applied | None |
| `Ready: False` + `validation` | Invalid YAML | Fix manifest syntax |
| `Ready: False` + `apply` | Kubernetes rejected | Check resource conflicts |
| `Ready: False` + `health` | Resources unhealthy | Check pod status |
| `Reconciling` | Apply in progress | Wait |

## Common Operations

### Force Immediate Sync

When you need changes applied now, not in 5 minutes:

```powershell
# Force GitRepository to re-fetch
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# Force Kustomization to re-apply
kubectl annotate kustomization ipc-platform-config-workloads -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

### Suspend GitOps

Temporarily stop Flux from making changes (maintenance window):

```powershell
# Suspend
kubectl patch kustomization ipc-platform-config-workloads -n flux-system `
  --type merge -p '{"spec":{"suspend":true}}'

# Resume
kubectl patch kustomization ipc-platform-config-workloads -n flux-system `
  --type merge -p '{"spec":{"suspend":false}}'
```

### View Sync History

```powershell
# Recent reconciliation events
kubectl describe kustomization ipc-platform-config-workloads -n flux-system

# Check events
kubectl get events -n flux-system --sort-by='.lastTimestamp' | Select-Object -Last 20
```

### Check What Will Be Applied

```powershell
# See the current applied revision
kubectl get gitrepository ipc-platform-config -n flux-system -o jsonpath='{.status.artifact.revision}'

# Compare with local Git
git log --oneline -5
```

## Drift Scenarios

### Scenario 1: Manual kubectl Edit

**Detection:**
- Resource configuration differs from Git manifest
- No corresponding Git commit

**Remediation:**
```powershell
# Force Flux to overwrite manual changes
kubectl annotate kustomization ipc-platform-config-workloads -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

### Scenario 2: Emergency Hotfix (Need to Keep)

**Detection:**
- Manual change was intentional
- Need to preserve the change in Git

**Remediation:**
```powershell
# Export current state
kubectl get deployment <name> -n dmc-workloads -o yaml > hotfix.yaml

# Clean up cluster-specific fields (status, uid, resourceVersion, etc.)
# Edit hotfix.yaml to match manifest format

# Copy to manifest location
Copy-Item hotfix.yaml .\kubernetes\workloads\<name>\deployment.yaml

# Commit to Git
git add .
git commit -m "fix: Capture emergency hotfix for <name>"
git push
```

### Scenario 3: Unexpected Resources

**Detection:**
- Resources exist in cluster but not in Git
- Often from debugging sessions or manual testing

**Remediation:**
```powershell
# If resource should not exist
kubectl delete <resource-type> <name> -n dmc-workloads

# If resource should be managed by GitOps
# Create manifest in Git, commit, and let Flux manage it
```

### Scenario 4: Missing Resources

**Detection:**
- Resource defined in Git but not in cluster
- Flux apply failed

**Investigation:**
```powershell
# Check Kustomization status for errors
kubectl describe kustomization ipc-platform-config-workloads -n flux-system

# Check kustomize-controller logs
kubectl logs -n flux-system deployment/kustomize-controller --tail=100 | Select-String "error"
```

**Common Causes:**
- Invalid YAML syntax
- Missing namespace
- Resource quota exceeded
- RBAC permission denied

## Troubleshooting Commands

### Full Flux Status

```powershell
# All Flux resources at a glance
kubectl get gitrepositories,kustomizations -n flux-system

# Detailed status
kubectl describe gitrepository ipc-platform-config -n flux-system
kubectl describe kustomization ipc-platform-config-workloads -n flux-system
```

### Controller Logs

```powershell
# Source controller (Git fetching)
kubectl logs -n flux-system deployment/source-controller --tail=100

# Kustomize controller (applying manifests)
kubectl logs -n flux-system deployment/kustomize-controller --tail=100

# Follow logs in real-time
kubectl logs -n flux-system deployment/kustomize-controller -f
```

### Network Connectivity

```powershell
# Test from cluster to Azure DevOps
kubectl run test-net --image=busybox --rm -it --restart=Never -- wget -qO- https://dev.azure.com

# Test DNS resolution
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup dev.azure.com
```

## Drift Prevention Best Practices

1. **Never use `kubectl edit` in production**
   - All changes through Git PRs
   - Emergency changes must be committed immediately after

2. **Label everything**
   - Use `managed-by: flux` labels
   - Makes it easy to identify GitOps-managed resources

3. **Enable pruning**
   - Set `prune: true` in Kustomization
   - Flux will remove resources deleted from Git

4. **Regular drift audits**
   - Run `Invoke-DriftDetection.ps1` weekly
   - Include in CI/CD as validation step

5. **Protect the flux-system namespace**
   - Restrict who can modify Flux resources
   - Changes to Flux config also through GitOps

## Emergency Procedures

### Complete Flux Reset

If Flux is badly broken:

```powershell
# Delete GitOps configuration (via Azure CLI)
az k8s-configuration flux delete `
  --name "ipc-platform-config" `
  --cluster-name "<your-arc-cluster-name>" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --yes

# Wait 30 seconds
Start-Sleep -Seconds 30

# Recreate
az k8s-configuration flux create `
  --name "ipc-platform-config" `
  --cluster-name "<your-arc-cluster-name>" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --namespace "flux-system" `
  --scope cluster `
  --url "https://dev.azure.com/<your-org>/IPC-Platform-Engineering/_git/IPC-Platform-Engineering" `
  --branch "main" `
  --kustomization name=workloads path=./kubernetes/workloads prune=true sync_interval=5m `
  --https-user "<your-org>" `
  --https-key "<PAT_TOKEN>"
```

### Rollback Deployment

To rollback to a previous version:

```powershell
# Option 1: Git revert (preferred)
git revert <commit-hash>
git push
# Flux will apply the reverted state

# Option 2: Manual image rollback (emergency only)
kubectl set image deployment/<name> <container>=<old-image> -n dmc-workloads
# MUST commit this change to Git immediately after
```
