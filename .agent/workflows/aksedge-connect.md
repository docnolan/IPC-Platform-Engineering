---
description: Connect to AKS Edge Essentials environment on <edge-vm-name> VM using PowerShell Direct
---

# AKS Edge Environment Connection

This workflow documents how to interact with the AKS Edge Essentials Kubernetes cluster running on the <edge-vm-name> Hyper-V VM.

## Prerequisites

- **Antigravity IDE must be running as Administrator** (required for Hyper-V access)
- VM `<edge-vm-name>` must be running
- PowerShell 7 (`pwsh`) is available on the host

## Environment Details

| Component | Value |
|-----------|-------|
| VM Name | `<edge-vm-name>` |
| VM Storage | `E:\Factory-VMs` |
| Kubernetes Version | v1.31.5 |
| Node Name | `desktop-amebs36-ledge` |
| GitOps | Flux CD syncing from Azure DevOps |

## Key Namespaces

| Namespace | Purpose |
|-----------|---------|
| `dmc-workloads` | Application simulators and gateways |
| `flux-system` | GitOps controllers |
| `azure-arc` | Azure Arc connectivity |
| `kube-system` | Core Kubernetes components |

## Connection Commands

### 1. Check if VM is running
// turbo
```powershell
pwsh -Command "Get-VM -Name '<edge-vm-name>' | Select-Object Name, State, Uptime"
```

### 2. Get all VMs on host
// turbo
```powershell
pwsh -Command "Get-VM | Select-Object Name, State, CPUUsage, MemoryAssigned"
```

### 3. Get VM network adapters
// turbo
```powershell
pwsh -Command "Get-VMNetworkAdapter -VMName '<edge-vm-name>' | Select-Object VMName, Name, SwitchName, IPAddresses"
```

### 4. Run kubectl commands inside VM
Use `Invoke-Command` with PowerShell Direct. The user will be prompted for VM credentials (Administrator account).

// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl get nodes }"
```

### 5. Common kubectl commands (all read-only, all turbo-enabled)

**Get all pods:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl get pods -A }"
```

**Check workload pods:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl get pods -n dmc-workloads }"
```

**Check GitOps status:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl get gitrepository,kustomization -n flux-system }"
```

**Check services:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl get svc -A }"
```

**Check deployments:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl get deployments -n dmc-workloads }"
```

**Check events:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl get events -n dmc-workloads --sort-by='.lastTimestamp' }"
```

**View pod logs:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl logs -n dmc-workloads deployment/opcua-simulator --tail=50 }"
```

**Check Flux sources:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { flux get sources git -A }"
```

**Check Flux kustomizations:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { flux get kustomizations -A }"
```

**Check AKS Edge node status:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { Get-AksEdgeNodeAddr -NodeType Linux }"
```

**Check AKS Edge deployment info:**
// turbo
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { Get-AksEdgeDeploymentInfo }"
```

### 6. Mutating commands (NOT turbo - require approval)

**Restart a deployment:**
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl rollout restart deployment/opcua-simulator -n dmc-workloads }"
```

**Force Flux reconciliation:**
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { flux reconcile source git ipc-platform-config -n flux-system }"
```

**Delete a pod (force restart):**
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { kubectl delete pod <pod-name> -n dmc-workloads }"
```

## Troubleshooting

### Permission denied error
Ensure Antigravity IDE is running as Administrator. Hyper-V cmdlets require elevated privileges.

### Credential prompt
Each `Invoke-Command` will prompt for the VM's local Administrator password. This is expected behavior for PowerShell Direct.

### VM not responding
```powershell
# Start the VM (requires approval - mutating)
pwsh -Command "Start-VM -Name '<edge-vm-name>'"
```
// turbo
```powershell
# Verify VM state (read-only)
pwsh -Command "Get-VM -Name '<edge-vm-name>' | Select-Object Name, State"
```

### Cluster not responding after VM restart
See wiki troubleshooting: The AKS Edge Linux VM may need to be restarted:
```powershell
pwsh -Command "Invoke-Command -VMName '<edge-vm-name>' -ScriptBlock { Stop-AksEdgeNode -NodeType Linux; Start-AksEdgeNode -NodeType Linux }"
```

## Workloads Reference

| Workload | Description |
|----------|-------------|
| `opcua-simulator` | Simulates OPC-UA server with industrial data |
| `opcua-gateway` | Connects OPC-UA to Kafka/cloud |
| `motion-simulator` | Motion control data simulator |
| `motion-gateway` | Motion data gateway |
| `ev-battery-simulator` | Electric vehicle battery telemetry |
| `vision-simulator` | Machine vision system simulator |
| `anomaly-detection` | ML-based anomaly detection |
| `health-monitor` | System health monitoring |
| `log-forwarder` | Log aggregation and forwarding |
| `test-data-collector` | Test data collection |
