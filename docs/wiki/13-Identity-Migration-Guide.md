# Identity & Security Migration — Implementation Guide

**Date:** 2026-02-05  
**Status:** Ready for Phased Implementation

---

## Overview

This guide walks through migrating the IPC Platform from secret-based to identity-based authentication.

| Component | Current | Target | Risk | Phase |
|-----------|---------|--------|------|-------|
| ACR Pull | Kubernetes Secret | Arc Managed Identity | Low | 1 |
| Flux Git | PAT | Workload Identity | Medium | 2 |
| IoT Hub | Connection String | Workload Identity | Low | 3 |

---

## Phase 1: ACR Managed Identity (Recommended First)

**Complexity:** Low  
**Risk:** Low  
**Rollback:** Easy

### Prerequisites

- Arc cluster connected: `aks-edge-ipc-factory-01`
- ACR exists: `<your-acr-name>`
- Az CLI logged in with Owner/UAA permissions

### Step 1.1: Run Setup Script

```powershell
# From your project directory
cd C:\Projects\IPC-Platform-Engineering\scripts

# Dry run first
.\setup-workload-identity.ps1 -Phase ACR -WhatIf

# Execute
.\setup-workload-identity.ps1 -Phase ACR
```

**Expected Output:**
```
Found Arc identity: <principal-id>
AcrPull role assigned to Arc identity
```

### Step 1.2: Update ImageRepositories

Apply the updated manifests to use `provider: azure`:

```powershell
# Option A: Update via GitOps (recommended)
# Edit gitops/infrastructure/sources/image-repositories.yaml
# Add: provider: azure
# Remove: secretRef

# Option B: Direct kubectl patch (for testing)
kubectl patch imagerepository anomaly-detection -n flux-system \
  --type=merge -p '{"spec":{"provider":"azure","secretRef":null}}'
```

### Step 1.3: Verify

```powershell
# Check ImageRepository status
kubectl get imagerepository -n flux-system

# Expected: All should show READY=True
NAME                 LAST SCAN              TAGS
anomaly-detection    2026-02-05T10:30:00Z   3
health-monitor       2026-02-05T10:30:00Z   3
...

# Check for auth errors
kubectl logs -n flux-system deploy/image-reflector-controller | Select-String "auth|error"
```

### Step 1.4: Remove imagePullSecrets from Deployments

After verifying ImageRepositories work, update deployments:

```yaml
# In each deployment, remove:
spec:
  template:
    spec:
      # DELETE THIS SECTION:
      imagePullSecrets:
        - name: acr-pull-secret
```

Or use Kustomize patch:

```yaml
# kustomization.yaml
patches:
  - patch: |-
      - op: remove
        path: /spec/template/spec/imagePullSecrets
    target:
      kind: Deployment
      namespace: ipc-workloads
```

### Step 1.5: Verify Pod Pulls

```powershell
# Restart a pod to test
kubectl rollout restart deployment/health-monitor -n ipc-workloads

# Check events for pull success
kubectl get events -n ipc-workloads --sort-by='.lastTimestamp' | Select-String "Pull"

# Should see "Successfully pulled image" without errors
```

### Rollback (if needed)

```powershell
# Re-add secretRef
kubectl patch imagerepository anomaly-detection -n flux-system \
  --type=merge -p '{"spec":{"secretRef":{"name":"acr-pull-secret"},"provider":null}}'

# Re-add imagePullSecrets to deployments
# (Revert the Kustomize patch or manually add back)
```

---

## Phase 2: Flux Workload Identity

**Complexity:** Medium-High  
**Risk:** Medium  
**Rollback:** Prepared

### Important Caveats

1. **AKS Edge Essentials may not support OIDC issuer** — this is a limitation of the lightweight K3s deployment
2. **Azure DevOps + Workload Identity** requires specific setup
3. **Alternative:** Keep PAT but store in Key Vault with rotation

### Step 2.1: Check OIDC Availability

```powershell
# Check if OIDC issuer is available
az connectedk8s show `
  --name aks-edge-ipc-factory-01 `
  --resource-group rg-ipc-platform `
  --query "oidcIssuerProfile.issuerUrl" -o tsv
```

**If empty or "null":** OIDC is not available. Skip to Alternative Approach below.

**If URL returned:** Continue with Step 2.2.

### Step 2.2: Run Setup Script (Flux Phase)

```powershell
.\setup-workload-identity.ps1 -Phase Flux -WhatIf
.\setup-workload-identity.ps1 -Phase Flux
```

**Expected Output:**
```
OIDC Issuer: https://oidc.prod-aks.azure.com/...
Created Managed Identity: mi-flux-gitops
Created Federated Identity Credential

Flux Configuration Values:
   AZURE_CLIENT_ID: <client-id>
   AZURE_TENANT_ID: <tenant-id>
```

### Step 2.3: Grant Azure DevOps Access

**Manual Step Required:**

1. Go to Azure DevOps → Organization Settings → Users
2. Add the Managed Identity (by Client ID or display name)
3. Grant "Reader" access to the repository

**Alternative:** Use Azure DevOps Service Connection with Workload Identity Federation.

### Step 2.4: Update Flux ServiceAccount

```powershell
# Patch the source-controller ServiceAccount
kubectl patch serviceaccount source-controller -n flux-system --type=merge -p @"
{
  "metadata": {
    "annotations": {
      "azure.workload.identity/client-id": "<AZURE_CLIENT_ID>"
    },
    "labels": {
      "azure.workload.identity/use": "true"
    }
  }
}
"@
```

### Step 2.5: Update GitRepository

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
  provider: azure  # Use Azure identity
  # secretRef removed
```

### Step 2.6: Verify

```powershell
# Check GitRepository status
kubectl get gitrepository -n flux-system

# Should show READY=True
NAME                  URL                                              AGE   READY
ipc-platform-config   https://dev.azure.com/.../IPC-Platform-Eng...    30d   True

# Check source-controller logs
kubectl logs -n flux-system deploy/source-controller | Select-String "azure|auth"
```

### Rollback (if needed)

```powershell
# Re-add secretRef
kubectl patch gitrepository ipc-platform-config -n flux-system \
  --type=merge -p '{"spec":{"secretRef":{"name":"flux-gitops-readonly"},"provider":null}}'

# Verify secret still exists
kubectl get secret flux-gitops-readonly -n flux-system
```

---

## Alternative: PAT in Key Vault

If OIDC is not available, use this approach for better secret management:

### Setup External Secrets Operator

```powershell
# Install ESO via Helm
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
```

### Create Key Vault Secrets

```powershell
az keyvault secret set --vault-name kv-ipc-platform --name flux-git-username --value "flux-readonly"
az keyvault secret set --vault-name kv-ipc-platform --name flux-git-pat --value "<your-pat>"
```

### Create ClusterSecretStore

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
spec:
  provider:
    azurekv:
      authType: ManagedIdentity
      vaultUrl: "https://kv-ipc-platform.vault.azure.net"
```

### Create ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: flux-gitops-readonly
  namespace: flux-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore
  target:
    name: flux-gitops-readonly
  data:
    - secretKey: username
      remoteRef:
        key: flux-git-username
    - secretKey: password
      remoteRef:
        key: flux-git-pat
```

**Benefits:**
- PAT stored in Key Vault (audited, centralized)
- Auto-syncs when you rotate PAT
- No manual Kubernetes secret management

---

## Verification Checklist

### Phase 1: ACR

- [ ] AcrPull role assigned to Arc identity
- [ ] ImageRepositories updated with `provider: azure`
- [ ] ImageRepositories show READY=True
- [ ] Pods pull images without imagePullSecrets
- [ ] No auth errors in image-reflector-controller logs

### Phase 2: Flux (if OIDC available)

- [ ] Managed Identity created
- [ ] Federated Credential created
- [ ] ServiceAccount annotated
- [ ] GitRepository updated with `provider: azure`
- [ ] GitRepository shows READY=True
- [ ] Flux sync continues working

### Alternative: Key Vault

- [ ] External Secrets Operator installed
- [ ] ClusterSecretStore created
- [ ] ExternalSecret syncing
- [ ] Flux using synced secret

---

## Documentation Updates

After implementation, update these wiki pages:

| Page | Update |
|------|--------|
| `03-Edge-Deployment.md` | ACR authentication method |
| `04-GitOps-Configuration.md` | Git authentication method |
| `12-Production-Roadmap.md` | Mark Phase 1/2 complete |

---

## Files Delivered

| File | Purpose |
|------|---------|
| `setup-workload-identity.ps1` | Azure resource provisioning script |
| `identity-auth-manifests.yaml` | Kubernetes manifest templates |
| `implementation-guide.md` | This step-by-step guide |
