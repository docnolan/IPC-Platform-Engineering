# ADR-0003: Workload Identity Federation for Azure Authentication

## Status
Accepted

## Date
2026-01-25

## Context
Platform workloads (health-monitor, log-forwarder, etc.) need to authenticate to Azure services:

- Log Analytics for telemetry upload
- IoT Hub for device communication
- Blob Storage for test data archival

Traditional approaches use service principal secrets stored as Kubernetes Secrets. This creates:
- Secret rotation burden
- Risk of secret leakage in Git or logs
- Compliance concerns for NIST 800-171 credential management

## Decision
We will use **Workload Identity Federation** for Azure authentication, eliminating the need for long-lived credentials.

Implementation:
- Azure AD App Registration with federated identity credential
- Kubernetes ServiceAccount annotated with Azure client ID
- Workloads use Azure.Identity SDK with `DefaultAzureCredential`

## Consequences

### Positive
- **No secrets**: No connection strings or keys to rotate or leak
- **Automatic rotation**: Token lifetime managed by Azure AD
- **Audit friendly**: Authentication tied to K8s ServiceAccount, traceable
- **NIST 800-171 compliant**: Addresses control 3.5.2 (Authenticator Management)

### Negative
- **Azure-specific**: Locks workloads to Azure (acceptable for this platform)
- **Setup complexity**: Requires Azure AD app, managed identity, and OIDC config
- **Arc requirement**: Workload Identity requires Arc-connected cluster

### Neutral
- Works with existing Azure SDKs via `DefaultAzureCredential`
- Fallback to secrets still possible for development/testing

## Alternatives Considered

### Service Principal Secrets
- Pros: Simple, widely understood
- Why not: Creates secret management burden, compliance risk

### Azure Key Vault CSI Driver
- Pros: Centralized secret store
- Why not: Still requires secrets, just stores them centrally

### Managed Identity (VM-based)
- Pros: Azure-native
- Why not: Tied to VM, not pod-level; doesn't work for Arc-connected K8s

## References
- [Workload Identity Federation](https://learn.microsoft.com/en-us/azure/active-directory/workload-identities/)
- [NIST 800-171 Control 3.5.2](https://nvd.nist.gov/800-171/Rev2/Control/3.5.2)
