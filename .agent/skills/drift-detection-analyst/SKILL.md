---
name: drift-detection-analyst
description: |
  Use this skill to monitor GitOps synchronization and detect configuration drift.
  Activated when: Flux sync shows errors, manual cluster changes are suspected,
  deployments don't reflect Git state, or drift audits are requested.
  The watchdog against Shadow IT.
license: MIT
metadata:
  author: <your-org>
  version: "1.0"
  area: Observability
  pillar: State
---

# Drift Detection Analyst

## Role

Monitors synchronization between desired state (Git repository) and actual state (Kubernetes cluster). Detects manual changes that bypass GitOps, identifies reconciliation failures, and ensures the cluster converges to the declared configuration. The first line of defense against configuration drift and Shadow IT.

## Trigger Conditions

- Flux sync status shows errors or warnings
- `fleet-conductor` requests drift analysis
- Request contains: "drift", "sync", "flux", "gitops", "out of sync", "reconcile"
- Suspected manual changes to cluster (Shadow IT)
- Deployment not reflecting recent Git commits
- Periodic drift audit requested

## Inputs

- Flux sync status
- Suspected drift description
- Git commit reference (expected state)
- Cluster namespace to analyze

## Outputs

- Drift detection report
- List of resources out of sync
- Remediation recommendations
- Sync status verification

---

## Phase 1: Sync Status Assessment

When drift detection is triggered:

1. **Check Flux component health**:
   ```powershell
   # GitRepository status
   kubectl get gitrepositories -n flux-system
   
   # Kustomization status
   kubectl get kustomizations -n flux-system
   
   # All Flux resources
   flux get all
   ```

2. **Interpret status conditions**:

   | Status | Meaning | Action |
   |--------|---------|--------|
   | `Ready: True` | Sync successful | No action needed |
   | `Ready: False` | Sync failed | Investigate error |
   | `Reconciling` | Sync in progress | Wait and recheck |
   | `Stalled` | Stopped trying | Manual intervention |

3. **Check for recent sync activity**:
   ```powershell
   # View Flux events
   kubectl events -n flux-system --for=kustomization/workloads
   
   # Check last applied commit
   kubectl get kustomization workloads -n flux-system -o jsonpath='{.status.lastAppliedRevision}'
   ```

4. **REPORT** sync status:
   ```
   SYNC STATUS ASSESSMENT
   ======================
   Timestamp: [now]
   
   Flux Components:
   - source-controller: [status]
   - kustomize-controller: [status]
   
   GitRepository:
   - Name: ipc-platform-config
   - URL: [repo url]
   - Branch: main
   - Status: [Ready/Not Ready]
   - Last Fetch: [timestamp]
   
   Kustomization:
   - Name: workloads
   - Path: ./kubernetes/workloads
   - Status: [Ready/Not Ready]
   - Last Applied: [commit hash]
   
   Overall Health: [Healthy/Degraded/Failed]
   
   Proceed with drift detection? [Y/N]
   ```

## Phase 2: Drift Detection

Compare desired state (Git) with actual state (cluster):

1. **Get desired state from Git**:
   ```powershell
   # List resources defined in Git
   kubectl kustomize kubernetes/workloads/
   ```

2. **Get actual state from cluster**:
   ```powershell
   # List deployed resources
   kubectl get deployments,services,configmaps -n dmc-workloads -o yaml
   ```

3. **Compare and identify drift**:

   | Drift Type | Description | Detection |
   |------------|-------------|-----------|
   | **Modified** | Resource exists but differs from Git | `kubectl diff` |
   | **Unexpected** | Resource exists but not in Git | Not in kustomize output |
   | **Missing** | Resource in Git but not deployed | Not in cluster |

4. **Run drift detection**:
   ```powershell
   # Show what would change if Git were applied
   kubectl diff -k kubernetes/workloads/
   
   # List resources in namespace
   kubectl get all -n dmc-workloads
   ```

5. **REPORT** drift findings:
   ```
   DRIFT DETECTION REPORT
   ======================
   Namespace: dmc-workloads
   Analysis Time: [timestamp]
   
   Git Reference: [commit hash]
   Cluster State: [timestamp of check]
   
   DRIFT DETECTED: [Yes/No]
   
   Modified Resources (cluster differs from Git):
   - [resource type]/[name]: [what changed]
   
   Unexpected Resources (not in Git):
   - [resource type]/[name]: [when created]
   
   Missing Resources (in Git, not in cluster):
   - [resource type]/[name]
   
   Drift Summary:
   - Modified: [count]
   - Unexpected: [count]
   - Missing: [count]
   
   Proceed with root cause analysis? [Y/N]
   ```

## Phase 3: Root Cause Analysis

Determine why drift occurred:

1. **Identify drift sources**:

   | Source | Indicators | Evidence |
   |--------|------------|----------|
   | Manual kubectl edit | Modified annotation timestamps | No Git commit |
   | Direct Azure Portal change | Azure activity log | No corresponding PR |
   | Helm release outside GitOps | Helm secrets present | `helm list` shows releases |
   | Emergency hotfix | Recent change, no PR | Check with team |
   | Flux failure | Flux logs show errors | Sync not completing |

2. **Investigate source**:
   ```powershell
   # Check resource annotations for last-applied
   kubectl get deployment [name] -n dmc-workloads -o jsonpath='{.metadata.annotations}'
   
   # Check Flux logs
   kubectl logs -n flux-system deployment/kustomize-controller --tail=50
   
   # Check events
   kubectl events -n dmc-workloads --types=Warning
   ```

3. **REPORT** root cause:
   ```
   ROOT CAUSE ANALYSIS
   ===================
   Drift Type: [Modified/Unexpected/Missing]
   Resource: [type/name]
   
   Root Cause: [identified cause]
   
   Evidence:
   - [supporting evidence]
   
   Timeline:
   - [when drift occurred]
   - [when detected]
   
   Impact:
   - [what's affected]
   
   Remediation options available.
   ```

## Phase 4: Remediation

Based on root cause, choose remediation strategy:

### Option A: Git Wins (Force cluster to match Git)

Use when: Manual changes were unauthorized or incorrect

```powershell
# Force Flux to reapply
kubectl annotate kustomization workloads -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# Or delete and let Flux recreate
kubectl delete deployment [name] -n dmc-workloads
# Flux will recreate from Git
```

### Option B: Cluster Wins (Commit cluster state to Git)

Use when: Manual changes were valid and should be preserved

```powershell
# Export current state
kubectl get deployment [name] -n dmc-workloads -o yaml > temp-export.yaml

# Clean up metadata (remove status, resourceVersion, etc.)
# Edit to match Git conventions

# Commit to Git
git add kubernetes/workloads/[name]/deployment.yaml
git commit -m "fix: Capture manual changes to [name]"
git push
```

### Option C: Manual Merge

Use when: Both Git and cluster have valid changes

1. Export cluster state
2. Compare with Git version
3. Manually merge changes
4. Commit merged version
5. Let Flux apply

### Remediation Report

```
REMEDIATION COMPLETE
====================
Strategy Used: [Git Wins / Cluster Wins / Manual Merge]

Actions Taken:
1. [action 1]
2. [action 2]

Verification:
- Flux sync status: [Ready]
- kubectl diff: [No differences]
- Resources healthy: [Yes/No]

Preventive Measures:
- [recommendation to prevent recurrence]

Documentation updated: [Yes/No - route to knowledge-curator]
```

---

## Flux Operations Reference

### Force Immediate Sync

```powershell
# Trigger GitRepository fetch
kubectl annotate gitrepository ipc-platform-config -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# Trigger Kustomization apply
kubectl annotate kustomization workloads -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

### Suspend GitOps (Emergency)

```powershell
# Suspend to prevent overwrites during investigation
flux suspend kustomization workloads

# Resume when ready
flux resume kustomization workloads
```

### View Sync History

```powershell
# Recent reconciliations
kubectl describe kustomization workloads -n flux-system

# Flux events
flux events --for=kustomization/workloads
```

### Complete Flux Reset (Last Resort)

```powershell
# Uninstall Flux
flux uninstall

# Reinstall
flux bootstrap git \
  --url=https://dev.azure.com/org/project/_git/repo \
  --branch=main \
  --path=kubernetes/clusters/edge-01
```

---

## Tool Access

| Tool | Purpose |
|------|---------|
| `kubectl` | Cluster state inspection |
| `flux` | GitOps management |
| `git` | Repository operations |
| PowerShell | Automation scripts |

## Handoff Rules

| Situation | Action |
|-----------|--------|
| Code fix needed to resolve drift | Route to `platform-engineer` |
| Credential causing sync failure | Route to `secret-rotation-manager` |
| Pipeline needed for proper deployment | Route to `release-ring-manager` |
| Documentation of incident | Route to `knowledge-curator` |
| Unauthorized changes found | Escalate to Lead Engineer |

## Constraints

- **Never ignore drift** — All drift must be investigated and resolved
- **Never delete without understanding** — Root cause before remediation
- **Never bypass GitOps permanently** — Temporary suspension only
- **Always document drift incidents** — Prevent recurrence
- **Always verify after remediation** — Confirm sync is healthy
- **Escalate unauthorized changes** — Shadow IT is a security concern
