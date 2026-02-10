# ADR-0004: Azure Container Registry for Image Distribution

## Status
Accepted

## Date
2026-01-20

## Context
Container images built by CI pipelines need to be stored and distributed to edge clusters. Requirements:

- Secure storage with vulnerability scanning
- Integrate with Azure DevOps pipelines
- Support image signing for supply chain security
- Accessible from Arc-connected edge clusters
- Comply with CUI handling requirements (CMMC Level 2)

## Decision
We will use **Azure Container Registry (ACR)** Premium tier for all container image storage.

Implementation:
- ACR instance: `<your-acr-name>.azurecr.io`
- Repository naming: `dmc/<workload-name>` (e.g., `dmc/health-monitor`)
- Tag strategy: Semantic versioning (`v1.0.0`) with `latest` for development
- Access: Pull via Kubernetes imagePullSecrets (transitioning to Workload Identity)
- Scanning: Microsoft Defender for Containers enabled

## Consequences

### Positive
- **Azure-native integration**: Works seamlessly with Azure DevOps and Arc
- **Geo-replication ready**: Premium tier can replicate for global deployments
- **Vulnerability scanning**: Microsoft Defender identifies CVEs
- **Content trust**: Cosign signing at repository level
- **RBAC**: Azure AD integration for access control

### Negative
- **Cost**: Premium tier required for security features
- **Azure lock-in**: Images stored in Azure (acceptable for this platform)
- **Pull secrets**: Currently requires imagePullSecret (migrating to Workload Identity)

### Neutral
- ACR admin account enabled for initial setup (should disable in production)
- Retention policy: Keep last 10 tags per repository

## Alternatives Considered

### Harbor
- Pros: Open source, self-hosted, rich features
- Why not: Additional infrastructure to manage; ACR already included in Azure

### Docker Hub
- Pros: Simple, widely used
- Why not: Not suitable for CUI data; public by default; rate limiting

### AWS ECR
- Pros: Similar feature set
- Why not: Platform is Azure-based; would require cross-cloud networking

### GitHub Container Registry
- Pros: GitHub integration
- Why not: Repository is in Azure DevOps; less Azure integration

## References
- [Azure Container Registry documentation](https://learn.microsoft.com/en-us/azure/container-registry/)
- [Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction)
