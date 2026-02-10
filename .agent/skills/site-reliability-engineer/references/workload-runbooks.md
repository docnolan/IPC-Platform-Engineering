# Workload Runbooks

Operational runbooks for each IPC Platform workload. Use these procedures for troubleshooting and recovery.

## Workload Inventory

| Workload | Purpose | Dependencies | Critical |
|----------|---------|--------------|----------|
| opcua-simulator | Generate test telemetry | None | No |
| opcua-gateway | Forward data to IoT Hub | IoT Hub, opcua-simulator | Yes |
| health-monitor | Collect system metrics | Log Analytics | Yes |
| log-forwarder | Stream security events | Log Analytics | Yes |
| anomaly-detection | Statistical alerting | health-monitor data | No |
| test-data-collector | Upload test results | Blob Storage | No |

## Startup Verification Sequence

After cluster start, verify workloads in this order:

```powershell
# 1. Wait for node ready
kubectl get nodes
# Expect: Ready status

# 2. Check flux-system
kubectl get pods -n flux-system
# Expect: All Running

# 3. Check workloads namespace
kubectl get pods -n dmc-workloads
# Expect: All Running

# 4. Verify data flow (check logs)
kubectl logs deployment/opcua-simulator -n dmc-workloads --tail=5
kubectl logs deployment/opcua-gateway -n dmc-workloads --tail=5
kubectl logs deployment/health-monitor -n dmc-workloads --tail=5
```

---

## Runbook: opcua-simulator

### Purpose
Generates simulated OPC-UA industrial telemetry (temperature, pressure, vibration) for demonstration and testing.

### Health Indicators
- Pod status: Running
- Logs show: "Published value" messages every 5 seconds
- No Python exceptions in logs

### Common Issues

#### Issue: No data being generated

**Symptoms:** Logs show no "Published value" messages

**Resolution:**
```powershell
# Check pod status
kubectl describe pod -l app=opcua-simulator -n dmc-workloads

# Restart the deployment
kubectl rollout restart deployment/opcua-simulator -n dmc-workloads

# Verify data flow
kubectl logs deployment/opcua-simulator -n dmc-workloads --tail=20 -f
```

#### Issue: Python exception in logs

**Symptoms:** Traceback in pod logs

**Resolution:**
```powershell
# Get full error
kubectl logs deployment/opcua-simulator -n dmc-workloads --tail=100

# Check environment variables
kubectl describe deployment/opcua-simulator -n dmc-workloads | Select-String "Environment" -Context 0,10

# If code issue: Route to ipc-junior-engineer
```

---

## Runbook: opcua-gateway

### Purpose
Reads from OPC-UA simulator and forwards telemetry to Azure IoT Hub.

### Health Indicators
- Pod status: Running
- Logs show: "Sent to IoT Hub" messages
- IoT Hub receiving data (check Azure Portal)

### Common Issues

#### Issue: Cannot connect to IoT Hub

**Symptoms:** Logs show connection errors or authentication failures

**Resolution:**
```powershell
# Check logs for specific error
kubectl logs deployment/opcua-gateway -n dmc-workloads --tail=50

# Verify IoT Hub environment variable
kubectl describe deployment/opcua-gateway -n dmc-workloads | Select-String "IOT_HUB"

# Verify IoT Hub exists
az iot hub show --name <your-iothub-name> --query "properties.state"

# If credential issue: Route to secret-rotation-manager
```

#### Issue: Cannot connect to simulator

**Symptoms:** Logs show OPC-UA connection errors

**Resolution:**
```powershell
# Verify simulator is running
kubectl get pods -l app=opcua-simulator -n dmc-workloads

# Check service exists
kubectl get service opcua-simulator -n dmc-workloads

# Test connectivity from gateway pod
kubectl exec deployment/opcua-gateway -n dmc-workloads -- python -c "import socket; socket.create_connection(('opcua-simulator', 4840))"
```

---

## Runbook: health-monitor

### Purpose
Collects Windows system metrics and sends to Azure Log Analytics.

### Health Indicators
- Pod status: Running
- Logs show: "Successfully sent" or metrics collection messages
- Data appearing in `IPCHealthMonitor_CL` table in Log Analytics

### Common Issues

#### Issue: Cannot send to Log Analytics

**Symptoms:** Logs show HTTP errors or authentication failures

**Resolution:**
```powershell
# Check logs for error
kubectl logs deployment/health-monitor -n dmc-workloads --tail=50

# Verify workspace ID environment variable
kubectl describe deployment/health-monitor -n dmc-workloads | Select-String "WORKSPACE"

# Test Log Analytics ingestion API (from Azure CLI)
az monitor log-analytics workspace show --workspace-name <your-workspace-name> --resource-group rg-ipc-platform-monitoring

# If credential issue: Route to secret-rotation-manager
```

#### Issue: Metrics not appearing in Log Analytics

**Symptoms:** Pod running but no data in table

**Resolution:**
```powershell
# Verify data is being sent
kubectl logs deployment/health-monitor -n dmc-workloads --tail=20

# Check Log Analytics (wait up to 5 minutes for ingestion)
# KQL query:
# IPCHealthMonitor_CL
# | where TimeGenerated > ago(30m)
# | take 10

# If no data after 10 minutes, check Data Collection Endpoint
```

---

## Runbook: log-forwarder

### Purpose
Reads Windows Security event logs and forwards to Azure Log Analytics for compliance.

### Health Indicators
- Pod status: Running
- Logs show: Security events being forwarded
- Data appearing in `IPCSecurityAudit_CL` table

### Common Issues

#### Issue: No security events captured

**Symptoms:** Logs show no events being read

**Resolution:**
```powershell
# This workload needs access to Windows event logs
# Verify it's running on Windows node with appropriate mounts

kubectl describe pod -l app=log-forwarder -n dmc-workloads

# Check volume mounts for event log access
# If running in Linux container, this is expected limitation

# For PoC: Security events may be simulated
```

#### Issue: Log Analytics ingestion errors

**Symptoms:** Similar to health-monitor ingestion issues

**Resolution:**
```powershell
# Same troubleshooting as health-monitor
# Check workspace ID, authentication, network connectivity
```

---

## Runbook: anomaly-detection

### Purpose
Performs statistical analysis (z-score) on telemetry to detect anomalies and generate alerts.

### Health Indicators
- Pod status: Running
- Logs show: Analysis cycles completing
- Anomaly events in Log Analytics when detected

### Common Issues

#### Issue: No anomalies detected

**Symptoms:** Running but never alerting (may be normal)

**Resolution:**
```powershell
# Check logs for analysis activity
kubectl logs deployment/anomaly-detection -n dmc-workloads --tail=50

# Verify it's receiving data (check for data messages)

# If data is stable, no anomalies is expected behavior
# To test: Manually spike values in simulator
```

#### Issue: Too many false positives

**Symptoms:** Alerting constantly on normal data

**Resolution:**
```powershell
# Check z-score threshold in environment variables
kubectl describe deployment/anomaly-detection -n dmc-workloads | Select-String "THRESHOLD"

# May need to adjust threshold (route to ipc-junior-engineer)
```

---

## Runbook: test-data-collector

### Purpose
Collects test stand results and uploads to Azure Blob Storage for archival.

### Health Indicators
- Pod status: Running
- Logs show: Upload success messages
- Files appearing in Blob container

### Common Issues

#### Issue: Cannot upload to Blob Storage

**Symptoms:** Logs show upload errors or authentication failures

**Resolution:**
```powershell
# Check logs
kubectl logs deployment/test-data-collector -n dmc-workloads --tail=50

# Verify storage account exists
az storage account show --name <storage-account> --query "provisioningState"

# Verify container exists
az storage container exists --name test-results --account-name <storage-account>

# If credential issue: Route to secret-rotation-manager
```

---

## Emergency Recovery Procedures

### All Pods Crashing

```powershell
# 1. Check node health
kubectl get nodes
kubectl describe node <node-name>

# 2. Check for cluster-wide issue
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | Select-Object -Last 20

# 3. Check Flux (may have applied bad config)
kubectl get kustomizations -n flux-system

# 4. If Flux applied bad config, suspend and revert
kubectl patch kustomization ipc-platform-config-workloads -n flux-system --type merge -p '{"spec":{"suspend":true}}'
# Then: git revert bad commit, resume Flux
```

### Node Not Ready

```powershell
# On the host machine (not in cluster)
# Check AKS Edge status
Import-Module AksEdge
Get-AksEdgeNodeAddr

# Restart the node
Stop-AksEdgeNode -NodeType Linux
Start-AksEdgeNode -NodeType Linux

# Wait 60 seconds, verify
kubectl get nodes
```

### Complete Workload Reset

```powershell
# Nuclear option: Delete and let GitOps recreate
kubectl delete namespace dmc-workloads

# Flux will recreate the namespace and all workloads
# Wait for reconciliation
kubectl get kustomizations -n flux-system -w

# Verify recreation
kubectl get pods -n dmc-workloads
```

---

## Data Flow Verification

To verify end-to-end data flow:

```powershell
# Step 1: Simulator generating data
kubectl logs deployment/opcua-simulator -n dmc-workloads --tail=5
# Expect: "Published value" messages

# Step 2: Gateway forwarding to IoT Hub
kubectl logs deployment/opcua-gateway -n dmc-workloads --tail=5
# Expect: "Sent to IoT Hub" messages

# Step 3: Health monitor sending metrics
kubectl logs deployment/health-monitor -n dmc-workloads --tail=5
# Expect: "Successfully sent" messages

# Step 4: Verify in Log Analytics (Azure Portal or KQL)
# IPCHealthMonitor_CL | where TimeGenerated > ago(15m) | take 10
```
