# ADR-0002: GitOps with Flux v2

## Status
Accepted

## Date
2026-01-20

## Context
The IPC Platform requires a deployment mechanism that:

- Supports zero-touch updates for 200+ edge devices
- Maintains Git as the single source of truth
- Enables rollback through Git history
- Works with Azure Arc-connected clusters
- Detects and reconciles configuration drift

Traditional push-based CI/CD (e.g., kubectl apply from pipelines) doesn't scale to hundreds of edge devices and lacks drift detection.

## Decision
We will use **Flux v2** as the GitOps operator for all Kubernetes deployments.

Implementation:
- Flux installed via Azure Arc GitOps extension
- Git repository: Azure DevOps with PAT-based authentication
- Image automation enabled for continuous delivery
- Kustomizations for environment-specific overlays

## Consequences

### Positive
- **Audit trail**: All changes logged in Git history
- **Zero-touch**: Edge devices pull their own updates
- **Drift reconciliation**: Flux automatically corrects unauthorized changes
- **Rollback**: `git revert` to restore any previous state
- **Scale**: No pipeline changes needed as device count grows
- **Image automation**: Flux can auto-update image tags when new builds complete

### Negative
- **Learning curve**: Teams must adopt GitOps mental model, not imperative commands
- **PAT management**: Azure DevOps PATs expire and must be rotated
- **Debugging complexity**: Must understand Flux reconciliation, not just kubectl
- **Sync lag**: ~5 minute delay between push and deployment (configurable)

### Neutral
- Requires Git repository structure discipline
- Secrets must be managed separately (External Secrets, sealed-secrets, or manual)

## Alternatives Considered

### ArgoCD
- Pros: Rich web UI, more advanced features
- Why not: Flux has better Azure Arc integration; smaller resource footprint for edge

### Azure DevOps Pipelines (push-based)
- Pros: Familiar CI/CD model, existing tooling
- Why not: Doesn't scale to 200+ devices; no drift detection; requires agent per device

### Rancher Fleet
- Pros: Purpose-built for multi-cluster
- Why not: Additional abstraction layer; less Azure-native integration

## References
- [Flux v2 documentation](https://fluxcd.io/flux/)
- [Azure Arc GitOps with Flux](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-gitops-flux2)
