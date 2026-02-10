# Troubleshooting Guide

This page documents common issues encountered during the PoC build and their solutions.

---

## AKS Edge Issues

### Cluster Not Responding After VM Restart

**Symptom:** `kubectl get nodes` hangs or returns error after the VM was restarted or powered off.

**Cause:** AKS Edge Linux VM wasn't gracefully stopped, leaving Kubernetes in an inconsistent state.

**Solution:**
```powershell
Import-Module AksEdge
Stop-AksEdgeNode -NodeType Linux
Start-Sleep -Seconds 30
Start-AksEdgeNode -NodeType Linux
Start-Sleep -Seconds 60
kubectl get nodes
```

**Prevention:** Always gracefully stop the Linux node before shutting down the VM:
```powershell
Import-Module AksEdge
Stop-AksEdgeNode -NodeType Linux
# Then shut down Windows
Stop-VM -Name "IPC-Factory-01"
```

---

### Calico CNI Authorization Failure

**Symptom:** Pods stuck in `ContainerCreating` with error:
```
plugin type="calico" failed (add): error getting ClusterInformation: connection is unauthorized: Unauthorized
```

**Symptoms in Detail:**
- `kubectl get pods -n kube-system` shows Calico pods in `Unknown` state
- New pods stuck in `ContainerCreating`
- `kubectl describe pod` shows Calico authorization errors in Events

**Cause:** When AKS Edge Linux VM is not gracefully stopped, Calico's internal tokens become invalid.

**Solution:** Same as above—restart the Linux node:
```powershell
Import-Module AksEdge
Stop-AksEdgeNode -NodeType Linux
Start-Sleep -Seconds 30
Start-AksEdgeNode -NodeType Linux

# Wait 60-90 seconds, then verify
kubectl get nodes
kubectl get pods -n kube-system
```

All `kube-system` pods should return to `Running` state.

---

### Pods Stuck in Pending

**Symptom:** Pods show `Pending` status indefinitely.

**Diagnosis:**
```powershell
kubectl describe pod <pod-name> -n ipc-workloads
# Check Events section at bottom of output
```

**Common Causes:**

| Cause | Events Message | Solution |
|-------|----------------|----------|
| Insufficient CPU | `Insufficient cpu` | Reduce resource requests or add node capacity |
| Insufficient Memory | `Insufficient memory` | Reduce resource requests or add node capacity |
| Missing Secret | `secret "xyz" not found` | Create the required secret |
| Image Pull Failure | `ErrImagePull` | See "Container Issues" section below |
| Node Not Ready | `0/1 nodes available` | Check node status with `kubectl get nodes` |

---

## Container Issues

### ErrImagePull / ImagePullBackOff

**Symptom:** Pod can't pull image from ACR:
```
failed to authorize: failed to fetch anonymous token: unexpected status... 401 Unauthorized
```

**Cause:** Azure Container Registry is private. Kubernetes needs credentials.

**Solution:**

1. **Verify secret exists:**
   ```powershell
   kubectl get secret acr-pull-secret -n ipc-workloads
   ```

2. **If missing, create the secret:**
   
   On workstation (to get password):
   ```powershell
   az acr update --name <your-acr-name> --admin-enabled true
   $ACR_PASSWORD = az acr credential show --name <your-acr-name> --query "passwords[0].value" -o tsv
   Write-Host $ACR_PASSWORD  # Copy this value
   ```
   
   On VM:
   ```powershell
   kubectl create secret docker-registry acr-pull-secret `
     --namespace ipc-workloads `
     --docker-server=<your-acr-name>.azurecr.io `
     --docker-username=<your-acr-name> `
     --docker-password=YOUR_ACR_PASSWORD
   ```

3. **Verify deployment references the secret:**
   ```powershell
   kubectl get deployment <name> -n ipc-workloads -o yaml | Select-String imagePullSecrets
   ```

4. **If missing from deployment, add to YAML:**
   ```yaml
   spec:
     template:
       spec:
         imagePullSecrets:
           - name: acr-pull-secret
         containers:
           # ...
   ```

---

### Container Not Using Latest Image

**Symptom:** Deployment shows old behavior after image push.

**Cause:** Kubernetes cached the image or the imagePullPolicy is not set correctly.

**Solution:**
```powershell
# Force pod recreation
kubectl rollout restart deployment/<name> -n ipc-workloads

# Or delete pods directly (Kubernetes will recreate them)
kubectl delete pods -n ipc-workloads -l app=<name>
```

**Prevention:** Use specific image tags (not `:latest`) and update the tag when pushing new images.

---

### CrashLoopBackOff

**Symptom:** Pod keeps restarting, status shows `CrashLoopBackOff`.

**Diagnosis:**
```powershell
# View container logs
kubectl logs deployment/<name> -n ipc-workloads --previous

# Describe pod for events
kubectl describe pod -n ipc-workloads -l app=<name>
```

**Common Causes:**

| Cause | Log Indicator | Solution |
|-------|---------------|----------|
| Missing env var | `KeyError` or `required` | Add missing environment variable to deployment |
| Bad connection string | `Authentication failed` | Verify secrets contain correct values |
| Import error | `ModuleNotFoundError` | Check Dockerfile installs dependencies |
| Syntax error | `SyntaxError` | Fix Python code and rebuild image |

---

## GitOps Issues

### Flux Not Syncing

**Symptom:** Changes pushed to Git don't appear on cluster.

**Diagnosis:**
```powershell
# Check GitRepository status
kubectl get gitrepositories -n flux-system

# Check Kustomization status
kubectl get kustomizations -n flux-system

# View source-controller logs
kubectl logs -n flux-system deployment/source-controller
```

**Force Immediate Sync:**
```powershell
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

---

### Flux Extension Stuck in "Creating"

**Symptom:** `az k8s-extension create` hangs for 30+ minutes.

**Cause:** Cluster was unhealthy when command ran, or previous failed installation left orphaned resources.

**Solution:**
```powershell
# Check extension status
az k8s-extension list `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --output table

# If stuck in "Creating", delete it
az k8s-extension delete `
  --name flux `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --yes

# Wait 30 seconds
Start-Sleep -Seconds 30

# Recreate
az k8s-extension create `
  --name flux `
  --extension-type microsoft.flux `
  --cluster-name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --cluster-type connectedClusters `
  --scope cluster
```

**Monitor progress:**
```powershell
kubectl get pods -n flux-system -w
```

Pods should progress: `Pending` → `ContainerCreating` → `Running` within 2-3 minutes.

---

### GitOps Configuration Authentication Failure

**Symptom:** Flux configuration shows `Non-Compliant` with error:
```
failed to checkout and determine revision: unable to clone '...': invalid pkt-len found
```

**Cause:** Azure DevOps repositories are private. Flux cannot anonymously clone.

**Solution:**

1. Create a Personal Access Token (PAT) in Azure DevOps:
   - Profile → Personal access tokens → New Token
   - Scopes: Code (Read)
   - Copy the token

2. Update Flux configuration:
   ```powershell
   az k8s-configuration flux update `
     --name "ipc-platform-config" `
     --cluster-name "aks-edge-ipc-factory-01" `
     --resource-group "rg-ipc-platform-arc" `
     --cluster-type connectedClusters `
     --https-user "<your-org>" `
     --https-key "YOUR_PAT_TOKEN"
   ```

---

### PAT Expired

**Symptom:** Flux suddenly stops syncing, authentication errors in logs.

**Solution:**
1. Generate new PAT in Azure DevOps (same process as above)
2. Update configuration with new token:
   ```powershell
   az k8s-configuration flux update `
     --name "ipc-platform-config" `
     --cluster-name "aks-edge-ipc-factory-01" `
     --resource-group "rg-ipc-platform-arc" `
     --cluster-type connectedClusters `
     --https-user "<your-org>" `
     --https-key "NEW_PAT_TOKEN"
   ```

**Prevention:** Set PAT expiration to 90+ days and add calendar reminder to rotate.

---

## Azure Connectivity

### Arc Shows Disconnected

**Diagnosis:**
```powershell
az connectedk8s show `
  --name "aks-edge-ipc-factory-01" `
  --resource-group "rg-ipc-platform-arc" `
  --query "connectivityStatus"
```

**Check Arc Agents:**
```powershell
kubectl get pods -n azure-arc
kubectl logs -n azure-arc deployment/clusterconnect-agent
```

**Common Causes:**
- VM has no internet connectivity
- Firewall blocking Azure endpoints
- Arc agent pod crashed

**Solution:**
```powershell
# Test connectivity from VM
Test-NetConnection -ComputerName "management.azure.com" -Port 443

# Restart Arc agents
kubectl rollout restart deployment -n azure-arc
```

---

### Log Analytics Not Receiving Data

**Checklist:**

1. **Verify secret exists:**
   ```powershell
   kubectl get secret azure-monitor-credentials -n ipc-workloads
   ```

2. **Check pod logs for HTTP errors:**
   ```powershell
   kubectl logs deployment/health-monitor -n ipc-workloads
   kubectl logs deployment/log-forwarder -n ipc-workloads
   ```

3. **Verify workspace ID and key are correct:**
   ```powershell
   kubectl get secret azure-monitor-credentials -n ipc-workloads -o yaml
   # Base64 decode the values and verify
   ```

4. **Data delay:** New data can take 5-10 minutes to appear in Log Analytics.

5. **Test query in Log Analytics:**
   ```kql
   IPCHealthMonitor_CL
   | take 10
   ```

---

### IoT Hub Not Receiving Messages

**Checklist:**

1. **Verify device exists:**
   ```powershell
   az iot hub device-identity show --hub-name "<your-iothub-name>" --device-id "ipc-factory-01"
   ```

2. **Check connection string secret:**
   ```powershell
   kubectl get secret iot-hub-connection -n ipc-workloads
   ```

3. **View workload logs:**
   ```powershell
   kubectl logs deployment/opcua-gateway -n ipc-workloads
   ```

4. **Monitor IoT Hub messages:**
   ```powershell
   az iot hub monitor-events --hub-name "<your-iothub-name>" --device-id "ipc-factory-01"
   ```

---

## Git Issues

### Branch Name Mismatch (master vs main)

**Symptom:** `git push origin main` fails:
```
error: src refspec main does not match any
```

**Cause:** Git created default branch as `master`, not `main`.

**Solution:**
```powershell
git branch -M main
git push origin main
```

---

### Git User Identity Not Configured

**Symptom:** First commit fails:
```
Author identity unknown
*** Please tell me who you are.
```

**Solution:**
```powershell
git config --global user.email "your-email@example.com"
git config --global user.name "Your Name"
```

---

## Azure Resource Provider Issues

### MissingSubscriptionRegistration

**Symptom:** Resource creation fails:
```
MissingSubscriptionRegistration: The subscription is not registered to use namespace 'Microsoft.ContainerRegistry'
```

**Cause:** Azure subscriptions must explicitly register resource providers before use.

**Solution:**
```powershell
# Register missing providers
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Devices
az provider register --namespace Microsoft.OperationalInsights

# Check registration status (wait for "Registered")
az provider show --namespace Microsoft.ContainerRegistry --query "registrationState" -o tsv
```

Registration takes 1-2 minutes per provider.

---

## Network Issues

### No Internet from Containers

**Diagnosis:**
```powershell
# Check DNS resolution
kubectl exec -it deployment/health-monitor -n ipc-workloads -- nslookup microsoft.com

# Check outbound connectivity
kubectl exec -it deployment/health-monitor -n ipc-workloads -- curl -I https://portal.azure.com
```

**Common Causes:**
- VM network adapter issue
- DNS not configured
- Firewall blocking outbound traffic

---

### Service-to-Service Communication Failure

**Symptom:** OPC-UA Gateway can't connect to OPC-UA Simulator.

**Diagnosis:**
```powershell
# Verify service exists
kubectl get svc -n ipc-workloads

# Test DNS resolution
kubectl exec -it deployment/opcua-gateway -n ipc-workloads -- nslookup opcua-simulator.ipc-workloads.svc.cluster.local

# Test connectivity
kubectl exec -it deployment/opcua-gateway -n ipc-workloads -- nc -zv opcua-simulator 4840
```

**Common Causes:**
- Service not created
- Wrong service name in environment variable
- Simulator pod not running

---

## Quick Diagnostic Commands

```powershell
# Overall cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Workload status
kubectl get pods -n ipc-workloads
kubectl get deployments -n ipc-workloads

# View recent events
kubectl get events -n ipc-workloads --sort-by='.lastTimestamp' | tail -20

# View logs for specific workload
kubectl logs deployment/health-monitor -n ipc-workloads --tail=50

# Describe problematic pod
kubectl describe pod <pod-name> -n ipc-workloads

# Check GitOps status
kubectl get gitrepositories,kustomizations -n flux-system

# Check Arc status
kubectl get pods -n azure-arc
az connectedk8s show --name "aks-edge-ipc-factory-01" --resource-group "rg-ipc-platform-arc" --query "connectivityStatus"
---

## Flux Image Automation

### Problem: Flux Image Automation Not Detecting New Images

**Symptoms:**
- `kubectl get imagerepositories` shows "not ready" or stale `lastScanTime`
- New container images pushed to ACR but deployments not updating

**Cause:**
- ACR credentials secret expired or misconfigured
- ImageRepository interval too long
- Network connectivity issues from cluster to ACR

**Solution:**

```powershell
# 1. Check ImageRepository status
kubectl get imagerepositories -n flux-system -o wide

# 2. Describe for detailed error
kubectl describe imagerepository health-monitor -n flux-system

# 3. Verify ACR credentials exist
kubectl get secret acr-credentials -n flux-system

# 4. Recreate credentials if needed
$acrPassword = az acr credential show --name <your-acr-name> --query "passwords[0].value" -o tsv

kubectl create secret docker-registry acr-credentials `
  --docker-server=<your-acr-name>.azurecr.io `
  --docker-username=<your-acr-name> `
  --docker-password=$acrPassword `
  -n flux-system --dry-run=client -o yaml | kubectl apply -f -

# 5. Force reconciliation
kubectl annotate imagerepository health-monitor -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

**Prevention:**
- Use Workload Identity Federation instead of static credentials
- Set up credential expiration monitoring alerts

---

### Problem: Image Tag Mismatch Between Git and Cluster

**Symptoms:**
- `kubectl get pods` shows different image tag than expected
- `kubectl diff` shows image tag differences
- Flux sync shows "Ready" but wrong version deployed

**Cause:**
- ImageUpdateAutomation committed to wrong branch
- Git commit succeeded but Flux hasn't synced yet
- Manual image tag edit directly in cluster (drift)

**Solution:**

```powershell
# 1. Check what Git says
git pull origin main
Get-Content kubernetes/workloads/health-monitor/deployment.yaml | Select-String "image:"

# 2. Check what cluster has
kubectl get deployment health-monitor -n ipc-workloads -o jsonpath='{.spec.template.spec.containers[0].image}'

# 3. Check Flux sync status
kubectl get kustomizations -n flux-system -o wide

# 4. Force Flux to reconcile
kubectl annotate kustomization workloads -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite

# 5. Wait and verify
Start-Sleep -Seconds 30
kubectl get pods -n ipc-workloads -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}'
```

**Prevention:**
- Never manually edit deployments in cluster (`kubectl edit`, `kubectl set image`)
- Always commit image changes to Git first
- Use `kubectl diff` to detect drift

---

### Problem: Bootstrap-Secrets.ps1 Fails with Access Denied

**Symptoms:**
- Script fails with "Forbidden", "Access Denied", or "Unauthorized"
- Secrets not created in cluster

**Cause:**
- Azure CLI not authenticated or wrong subscription
- Service Principal lacks Key Vault access policy
- kubeconfig not configured for target cluster

**Solution:**

```powershell
# 1. Verify Azure authentication
az account show --query "{User:user.name, Subscription:name}"

# 2. Set correct subscription
az account set --subscription "IPC-Platform"

# 3. Verify Key Vault access
$vaultName = "kv-ipc-platform"
az keyvault secret list --vault-name $vaultName --query "[].name" -o table

# 4. Verify kubectl access
kubectl auth can-i create secrets -n ipc-workloads

# 5. Check current kubeconfig context
kubectl config current-context

# 6. Run with verbose output
.\scripts\Bootstrap-Secrets.ps1 -Verbose
```

**If Key Vault access denied:**
```powershell
# Add access policy for current user
$userId = az ad signed-in-user show --query id -o tsv
az keyvault set-policy --name $vaultName --object-id $userId `
  --secret-permissions get list
```

**Prevention:**
- Use Workload Identity Federation for Azure access
- Document required RBAC roles in setup guide
- Test script with `--WhatIf` first

---

### Problem: blob-storage-connection Secret Missing

**Symptoms:**
- test-data-collector pod in `CrashLoopBackOff`
- Logs show `KeyError: 'BLOB_CONNECTION_STRING'` or similar

**Cause:**
- Secret not created during initial cluster setup
- Secret name mismatch between deployment and actual secret

**Solution:**

```powershell
# 1. Check if secret exists
kubectl get secret blob-storage-connection -n ipc-workloads

# 2. If missing, get connection string from Key Vault
$connectionString = az keyvault secret show `
  --vault-name "kv-ipc-platform" `
  --name "blob-storage-connection-string" `
  --query value -o tsv

# 3. Create the secret
kubectl create secret generic blob-storage-connection `
  --from-literal=connectionString=$connectionString `
  -n ipc-workloads

# 4. Restart the pod to pick up new secret
kubectl rollout restart deployment/test-data-collector -n ipc-workloads

# 5. Verify pod is running
kubectl get pods -n ipc-workloads -l app=test-data-collector
```

**Prevention:**
- Include in Bootstrap-Secrets.ps1 script
- Add to secrets checklist in [03-Edge-Deployment.md](03-Edge-Deployment.md)
- Use `optional: false` in secretKeyRef to fail fast

---

### Problem: binascii Base64 Padding Error

**Symptoms:**
- Python workload crashes with `binascii.Error: Incorrect padding`
- Occurs when decoding base64-encoded secrets

**Cause:**
- Secret value not properly base64-encoded when created manually
- Extra whitespace or newlines in secret value
- Copy/paste error truncated the secret

**Solution:**

```powershell
# 1. Check the raw secret value (will be base64-encoded)
$encoded = kubectl get secret iot-hub-connection -n ipc-workloads `
  -o jsonpath='{.data.connectionString}'

# 2. Test if it's valid base64
try {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))
    Write-Host "Secret is valid base64" -ForegroundColor Green
} catch {
    Write-Host "Secret has invalid base64 encoding!" -ForegroundColor Red
}

# 3. If invalid, recreate with proper encoding using --from-literal
# (kubectl automatically base64-encodes when using --from-literal)
$plainValue = "HostName=iothub.azure-devices.net;DeviceId=..."

kubectl create secret generic iot-hub-connection `
  --from-literal=connectionString=$plainValue `
  -n ipc-workloads --dry-run=client -o yaml | kubectl apply -f -

# 4. Restart affected pods
kubectl rollout restart deployment -n ipc-workloads
```

**Prevention:**
- Always use `--from-literal` instead of manually base64-encoding
- Use Bootstrap-Secrets.ps1 for consistent secret creation
- Validate secrets immediately after creation

---

## Related Pages

- [Edge Deployment](03-Edge-Deployment.md) — AKS Edge configuration
- [GitOps Configuration](04-GitOps-Configuration.md) — Flux setup, Image Automation
- [Quick Reference](A2-Quick-Reference.md) — Commands cheat sheet
- [Demo Script](11-Demo-Script.md) — Backup plans for demo failures

