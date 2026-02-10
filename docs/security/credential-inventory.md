# Credential Inventory

> [!WARNING]
> **DO NOT COMMIT ACTUAL SECRETS TO THIS FILE.**
> This document logs the existence and storage location of credentials, NEVER the values themselves.

## Inventory Table

| Credential Name | Service / System | Storage Location | KeyVault Name | Rotation Schedule | Owner |
|-----------------|------------------|------------------|---------------|-------------------|-------|
| IPC-Platform-SP | Azure Service Principal | Azure Key Vault | `kv-ipc-platform-prod` | Annually | Platform Team |
| Flux-Git-PAT | Azure DevOps | K8s Secret | N/A | Every 6 Months | Platform Team |
| ACR-Admin-Creds | Container Registry | Disabled (WIF Used)| N/A | N/A | N/A |
| IoT-Hub-Connect | IoT Hub | K8s Secret | N/A | On Breach | SRE Team |

## Rotation Procedures
Refer to `scripts/security/rotate-credentials.ps1` for automated rotation logic.
