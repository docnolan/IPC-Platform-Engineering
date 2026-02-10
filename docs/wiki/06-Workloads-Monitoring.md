# Monitoring Workloads

This page documents the **Health Monitor** and **Log Forwarder** containerized workloads that provide system observability and compliance audit logging.

---

## Overview

Both workloads send data to Azure Log Analytics, enabling centralized monitoring across all deployed IPCs from a single dashboard.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  IPC (Windows 10 IoT Enterprise)                                            │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  Performance Counters, Service Status, Windows Event Logs            │  │
│  └─────────────────────────────────┬─────────────────────────────────────┘  │
│                                    │                                        │
│  ┌─────────────────────────────────▼─────────────────────────────────────┐  │
│  │  AKS Edge Essentials (K3s)                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │  │
│  │  │  Health Monitor                                                 │ │  │
│  │  │  - Collects CPU, memory, disk metrics                          │──┼──┼──► Azure Log Analytics
│  │  │  - Monitors network connectivity                                │ │  │    (IPCHealthMonitor_CL)
│  │  │  - Sends heartbeats every 60 seconds                           │ │  │
│  │  └─────────────────────────────────────────────────────────────────┘ │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │  │
│  │  │  Log Forwarder                                                  │ │  │
│  │  │  - Simulates Windows Security Event collection                  │──┼──┼──► Azure Log Analytics
│  │  │  - Maps events to NIST 800-171 controls                        │ │  │    (IPCSecurityAudit_CL)
│  │  │  - 90-day tamper-proof retention                               │ │  │
│  │  └─────────────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Health Monitor

### Purpose

Collects IPC health metrics and sends them to Azure Log Analytics for centralized monitoring. Enables proactive support by detecting issues before customers report them.

### Metrics Collected

| Category | Metric | Alert Threshold |
|----------|--------|-----------------|
| CPU | Utilization % | > 90% = Warning |
| Memory | Usage % | > 90% = Warning |
| Disk | Usage % | > 85% = Warning |
| Network | Endpoint reachability | Unreachable = Critical |
| Temperature | CPU temp (if available) | Informational |

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/health-monitor/Dockerfile` |
| Python source | `docker/health-monitor/src/monitor.py` |
| K8s deployment | `kubernetes/workloads/health-monitor/deployment.yaml` |

### Dockerfile

**Path:** `C:\Projects\IPC-Platform-Engineering\docker\health-monitor\Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir psutil requests

COPY src/monitor.py .

CMD ["python", "monitor.py"]
```

### Python Source Code

**Path:** `C:\Projects\IPC-Platform-Engineering\docker\health-monitor\src\monitor.py`

```python
"""
Panel Health Monitor
Collects system metrics and sends to Azure Monitor
"""

import os
import time
import socket
import psutil
import json
from datetime import datetime
import requests
import hashlib
import hmac
import base64

# Configuration
DEVICE_ID = os.getenv("HOSTNAME", socket.gethostname())
CUSTOMER_ID = os.getenv("CUSTOMER_ID", "dmc-internal")
LOG_ANALYTICS_WORKSPACE_ID = os.getenv("LOG_ANALYTICS_WORKSPACE_ID", "")
LOG_ANALYTICS_KEY = os.getenv("LOG_ANALYTICS_KEY", "")
COLLECTION_INTERVAL = int(os.getenv("COLLECTION_INTERVAL", "60"))

# Services to monitor (customize per deployment)
MONITORED_SERVICES = [
    "Ignition Gateway",
    "KEPServerEX",
    "RSLinx",
    "W3SVC",  # IIS
]

# Network endpoints to check (PLCs, HMIs)
NETWORK_ENDPOINTS = [
    ("opcua-simulator", 4840),
]

def collect_system_metrics():
    """Collect system health metrics"""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    # Get CPU temperature if available (Linux)
    try:
        temps = psutil.sensors_temperatures()
        cpu_temp = temps.get('coretemp', [{}])[0].get('current', 0)
    except:
        cpu_temp = 0
    
    return {
        "cpu_percent": cpu_percent,
        "memory_percent": memory.percent,
        "memory_used_gb": round(memory.used / (1024**3), 2),
        "memory_total_gb": round(memory.total / (1024**3), 2),
        "disk_percent": disk.percent,
        "disk_used_gb": round(disk.used / (1024**3), 2),
        "disk_total_gb": round(disk.total / (1024**3), 2),
        "cpu_temperature": cpu_temp,
        "boot_time": datetime.fromtimestamp(psutil.boot_time()).isoformat()
    }

def check_network_endpoints():
    """Check connectivity to critical network endpoints"""
    results = {}
    for host, port in NETWORK_ENDPOINTS:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((host, port))
            results[f"{host}:{port}"] = "reachable" if result == 0 else "unreachable"
            sock.close()
        except Exception as e:
            results[f"{host}:{port}"] = f"error: {str(e)}"
    return results

def send_to_log_analytics(data):
    """Send data to Azure Log Analytics"""
    if not LOG_ANALYTICS_WORKSPACE_ID or not LOG_ANALYTICS_KEY:
        print("  Log Analytics not configured, skipping upload")
        return
    
    body = json.dumps(data)
    content_length = len(body)
    rfc1123date = datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S GMT')
    
    string_to_hash = f"POST\n{content_length}\napplication/json\nx-ms-date:{rfc1123date}\n/api/logs"
    bytes_to_hash = string_to_hash.encode('utf-8')
    decoded_key = base64.b64decode(LOG_ANALYTICS_KEY)
    encoded_hash = base64.b64encode(hmac.new(decoded_key, bytes_to_hash, digestmod=hashlib.sha256).digest()).decode('utf-8')
    authorization = f"SharedKey {LOG_ANALYTICS_WORKSPACE_ID}:{encoded_hash}"
    
    uri = f"https://{LOG_ANALYTICS_WORKSPACE_ID}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': authorization,
        'Log-Type': 'IPCHealthMonitor',
        'x-ms-date': rfc1123date
    }
    
    response = requests.post(uri, data=body, headers=headers)
    if response.status_code >= 200 and response.status_code <= 299:
        print("  -> Sent to Log Analytics")
    else:
        print(f"  -> Log Analytics error: {response.status_code} - {response.text}")

def main():
    print(f"Health Monitor starting for device: {DEVICE_ID}")
    print(f"Customer: {CUSTOMER_ID}")
    print(f"Collection interval: {COLLECTION_INTERVAL} seconds")
    
    while True:
        timestamp = datetime.utcnow().isoformat() + "Z"
        
        # Collect metrics
        metrics = collect_system_metrics()
        network = check_network_endpoints()
        
        # Build health record
        health_record = {
            "timestamp": timestamp,
            "deviceId": DEVICE_ID,
            "customerId": CUSTOMER_ID,
            "system": metrics,
            "network": network,
            "status": "healthy"
        }
        
        # Determine overall status
        if metrics["cpu_percent"] > 90:
            health_record["status"] = "warning"
            health_record["alerts"] = health_record.get("alerts", []) + ["High CPU usage"]
        if metrics["memory_percent"] > 90:
            health_record["status"] = "warning"
            health_record["alerts"] = health_record.get("alerts", []) + ["High memory usage"]
        if metrics["disk_percent"] > 85:
            health_record["status"] = "warning"
            health_record["alerts"] = health_record.get("alerts", []) + ["Low disk space"]
        if any("unreachable" in v for v in network.values()):
            health_record["status"] = "critical"
            health_record["alerts"] = health_record.get("alerts", []) + ["Network endpoint unreachable"]
        
        print(f"\n[{timestamp}] Health Status: {health_record['status']}")
        print(f"  CPU: {metrics['cpu_percent']}%  Memory: {metrics['memory_percent']}%  Disk: {metrics['disk_percent']}%")
        
        if health_record.get("alerts"):
            print(f"  ALERTS: {', '.join(health_record['alerts'])}")
        
        # Send to Azure
        send_to_log_analytics(health_record)
        
        time.sleep(COLLECTION_INTERVAL)

if __name__ == "__main__":
    main()
```

### Kubernetes Deployment

**Path:** `C:\Projects\IPC-Platform-Engineering\kubernetes\workloads\health-monitor\deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-monitor
  namespace: ipc-workloads
  labels:
    app: health-monitor
    component: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: health-monitor
  template:
    metadata:
      labels:
        app: health-monitor
        component: monitoring
    spec:
      containers:
        - name: health-monitor
          image: <your-acr-name>.azurecr.io/ipc/health-monitor:latest
          env:
            - name: CUSTOMER_ID
              value: "dmc-demo"
            - name: COLLECTION_INTERVAL
              value: "60"
            - name: LOG_ANALYTICS_WORKSPACE_ID
              valueFrom:
                secretKeyRef:
                  name: azure-monitor-credentials
                  key: workspaceId
                  optional: true
            - name: LOG_ANALYTICS_KEY
              valueFrom:
                secretKeyRef:
                  name: azure-monitor-credentials
                  key: workspaceKey
                  optional: true
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"
      imagePullSecrets:
        - name: acr-pull-secret
```

---

## Log Forwarder

### Purpose

Forwards Windows Security Event Log entries to Azure Log Analytics for CMMC/NIST 800-171 compliance auditing. In the PoC, this generates simulated events; in production, it would use Windows Event Forwarding or Azure Monitor Agent.

### Simulated Events

| Event ID | Event Type | Description | NIST Control |
|----------|------------|-------------|--------------|
| 4624 | Logon | An account was successfully logged on | 3.3.1, 3.3.2 |
| 4625 | FailedLogon | An account failed to log on | 3.3.1, 3.3.2 |
| 4634 | Logoff | An account was logged off | 3.3.1 |
| 4648 | ExplicitCredential | A logon was attempted using explicit credentials | 3.3.1 |
| 4672 | SpecialPrivilege | Special privileges assigned to new logon | 3.1.7 |
| 4688 | ProcessCreation | A new process has been created | 3.3.1 |
| 4697 | ServiceInstall | A service was installed in the system | 3.3.2 |
| 4719 | AuditPolicyChange | System audit policy was changed | 3.3.2 |
| 4738 | AccountChange | A user account was changed | 3.3.2 |
| 4756 | GroupMembership | A member was added to a security-enabled group | 3.3.2 |

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/log-forwarder/Dockerfile` |
| Python source | `docker/log-forwarder/src/forwarder.py` |
| K8s deployment | `kubernetes/workloads/log-forwarder/deployment.yaml` |

### Dockerfile

**Path:** `C:\Projects\IPC-Platform-Engineering\docker\log-forwarder\Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir requests pytz

COPY src/forwarder.py .

CMD ["python", "forwarder.py"]
```

### Python Source Code

**Path:** `C:\Projects\IPC-Platform-Engineering\docker\log-forwarder\src\forwarder.py`

```python
"""
Compliance Audit Log Forwarder
Forwards Windows-style security events to Azure Log Analytics
Note: In production, this would use Windows Event Forwarding or Azure Monitor Agent
For the PoC, this simulates the log forwarding pattern
"""

import os
import json
import time
import hashlib
import hmac
import base64
import requests
from datetime import datetime
import random

# Configuration
DEVICE_ID = os.getenv("HOSTNAME", "unknown-device")
CUSTOMER_ID = os.getenv("CUSTOMER_ID", "ipc-internal")
LOG_ANALYTICS_WORKSPACE_ID = os.getenv("LOG_ANALYTICS_WORKSPACE_ID", "")
LOG_ANALYTICS_KEY = os.getenv("LOG_ANALYTICS_KEY", "")
FORWARD_INTERVAL = int(os.getenv("FORWARD_INTERVAL", "30"))

# Simulated security events for demo
# In production, these would come from Windows Event Log API
DEMO_EVENTS = [
    {"EventID": 4624, "EventType": "Logon", "Description": "An account was successfully logged on"},
    {"EventID": 4625, "EventType": "FailedLogon", "Description": "An account failed to log on"},
    {"EventID": 4634, "EventType": "Logoff", "Description": "An account was logged off"},
    {"EventID": 4648, "EventType": "ExplicitCredential", "Description": "A logon was attempted using explicit credentials"},
    {"EventID": 4672, "EventType": "SpecialPrivilege", "Description": "Special privileges assigned to new logon"},
    {"EventID": 4688, "EventType": "ProcessCreation", "Description": "A new process has been created"},
    {"EventID": 4697, "EventType": "ServiceInstall", "Description": "A service was installed in the system"},
    {"EventID": 4719, "EventType": "AuditPolicyChange", "Description": "System audit policy was changed"},
    {"EventID": 4738, "EventType": "AccountChange", "Description": "A user account was changed"},
    {"EventID": 4756, "EventType": "GroupMembership", "Description": "A member was added to a security-enabled group"},
]

def generate_simulated_event():
    """Generate a realistic-looking security event for demo"""
    event_template = random.choice(DEMO_EVENTS)
    
    return {
        "TimeGenerated": datetime.utcnow().isoformat() + "Z",
        "EventID": event_template["EventID"],
        "EventType": event_template["EventType"],
        "Description": event_template["Description"],
        "Computer": DEVICE_ID,
        "CustomerId": CUSTOMER_ID,
        "SourceSystem": "WindowsSecurityEvent",
        "Channel": "Security",
        "Account": f"IPC\\{'operator' if random.random() > 0.3 else 'admin'}{random.randint(1,5)}",
        "LogonType": random.choice([2, 3, 10]) if "Logon" in event_template["EventType"] else None,
        "IpAddress": f"192.168.1.{random.randint(1, 254)}",
        "ComplianceFramework": ["NIST-800-171", "CMMC-L2"],
        "RetentionDays": 90
    }

def send_to_log_analytics(events):
    """Send events to Azure Log Analytics"""
    if not LOG_ANALYTICS_WORKSPACE_ID or not LOG_ANALYTICS_KEY:
        print("  Log Analytics not configured")
        return False
    
    body = json.dumps(events)
    content_length = len(body)
    rfc1123date = datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S GMT')
    
    string_to_hash = f"POST\n{content_length}\napplication/json\nx-ms-date:{rfc1123date}\n/api/logs"
    bytes_to_hash = string_to_hash.encode('utf-8')
    decoded_key = base64.b64decode(LOG_ANALYTICS_KEY)
    encoded_hash = base64.b64encode(
        hmac.new(decoded_key, bytes_to_hash, digestmod=hashlib.sha256).digest()
    ).decode('utf-8')
    authorization = f"SharedKey {LOG_ANALYTICS_WORKSPACE_ID}:{encoded_hash}"
    
    uri = f"https://{LOG_ANALYTICS_WORKSPACE_ID}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': authorization,
        'Log-Type': 'IPCSecurityAudit',
        'x-ms-date': rfc1123date,
        'time-generated-field': 'TimeGenerated'
    }
    
    response = requests.post(uri, data=body, headers=headers)
    return response.status_code >= 200 and response.status_code <= 299

def main():
    print(f"Compliance Log Forwarder starting for device: {DEVICE_ID}")
    print(f"Customer: {CUSTOMER_ID}")
    print(f"Forward interval: {FORWARD_INTERVAL} seconds")
    print(f"Compliance frameworks: NIST 800-171, CMMC Level 2")
    print(f"Retention: 90 days")
    
    event_count = 0
    
    while True:
        # Generate batch of events (simulating real event collection)
        batch_size = random.randint(1, 5)
        events = [generate_simulated_event() for _ in range(batch_size)]
        event_count += batch_size
        
        print(f"\n[{datetime.utcnow().isoformat()}Z] Forwarding {batch_size} security events...")
        
        # Print summary of events
        for event in events:
            print(f"  - Event {event['EventID']}: {event['EventType']} ({event['Account']})")
        
        # Send to Log Analytics
        if send_to_log_analytics(events):
            print(f"  -> Forwarded to Log Analytics (total: {event_count})")
        else:
            print(f"  -> Events logged locally (Log Analytics not configured)")
        
        time.sleep(FORWARD_INTERVAL)

if __name__ == "__main__":
    main()
```

### Kubernetes Deployment

**Path:** `C:\Projects\IPC-Platform-Engineering\kubernetes\workloads\log-forwarder\deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-forwarder
  namespace: ipc-workloads
  labels:
    app: log-forwarder
    component: compliance
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-forwarder
  template:
    metadata:
      labels:
        app: log-forwarder
        component: compliance
    spec:
      containers:
        - name: log-forwarder
          image: <your-acr-name>.azurecr.io/ipc/log-forwarder:latest
          env:
            - name: CUSTOMER_ID
              value: "dmc-demo"
            - name: FORWARD_INTERVAL
              value: "30"
            - name: LOG_ANALYTICS_WORKSPACE_ID
              valueFrom:
                secretKeyRef:
                  name: azure-monitor-credentials
                  key: workspaceId
                  optional: true
            - name: LOG_ANALYTICS_KEY
              valueFrom:
                secretKeyRef:
                  name: azure-monitor-credentials
                  key: workspaceKey
                  optional: true
          resources:
            requests:
              memory: "32Mi"
              cpu: "25m"
            limits:
              memory: "64Mi"
              cpu: "50m"
      imagePullSecrets:
        - name: acr-pull-secret
```

---

## Shared Secret: Azure Monitor Credentials

Both workloads require the `azure-monitor-credentials` secret containing Log Analytics authentication.

### Create the Secret

```powershell
# On the VM (IPC-Factory-01)

# Retrieve workspace key
$workspaceKey = az monitor log-analytics workspace get-shared-keys `
  --resource-group "rg-ipc-platform-monitoring" `
  --workspace-name "<your-workspace-name>" `
  --query primarySharedKey -o tsv

# Create secret
kubectl create secret generic azure-monitor-credentials `
  --namespace ipc-workloads `
  --from-literal=workspaceId="<your-workspace-id>" `
  --from-literal=workspaceKey="$workspaceKey"
```

### Verify Secret

```powershell
kubectl get secret azure-monitor-credentials -n ipc-workloads -o yaml
```

---

## Build and Deploy

### Build Health Monitor

```powershell
# From development machine
az acr build --registry <your-acr-name> `
  --image ipc/health-monitor:latest `
  --file docker/health-monitor/Dockerfile `
  docker/health-monitor/
```

### Build Log Forwarder

```powershell
az acr build --registry <your-acr-name> `
  --image ipc/log-forwarder:latest `
  --file docker/log-forwarder/Dockerfile `
  docker/log-forwarder/
```

### Deploy via GitOps

1. Commit deployment manifests to `kubernetes/workloads/` directory
2. Push to Azure DevOps repository
3. Flux automatically syncs within 5 minutes
4. Verify deployment:

```powershell
# On VM
kubectl get pods -n ipc-workloads -l component=monitoring
kubectl get pods -n ipc-workloads -l component=compliance
```

---

## Verification

### Check Pod Status

```powershell
kubectl get pods -n ipc-workloads | Select-String "health-monitor|log-forwarder"
```

Expected output:
```
health-monitor-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
log-forwarder-xxxxxxxxxx-xxxxx    1/1     Running   0          5m
```

### View Health Monitor Logs

```powershell
kubectl logs -n ipc-workloads -l app=health-monitor --tail=20
```

Expected output:
```
Health Monitor starting for device: health-monitor-7f8b5c9d4-k2n3m
Customer: ipc-demo
Collection interval: 60 seconds

[2026-01-23T15:30:00Z] Health Status: healthy
  CPU: 12%  Memory: 45%  Disk: 32%
  -> Sent to Log Analytics
```

### View Log Forwarder Logs

```powershell
kubectl logs -n ipc-workloads -l app=log-forwarder --tail=20
```

Expected output:
```
Compliance Log Forwarder starting for device: log-forwarder-6c4d7b8e5-m4n5p
Customer: ipc-demo
Forward interval: 30 seconds
Compliance frameworks: NIST 800-171, CMMC Level 2
Retention: 90 days

[2026-01-23T15:30:00Z] Forwarding 3 security events...
  - Event 4624: Logon (IPC\operator2)
  - Event 4688: ProcessCreation (IPC\admin1)
  - Event 4672: SpecialPrivilege (IPC\operator4)
  -> Forwarded to Log Analytics (total: 15)
```

### Query Log Analytics

After 5-10 minutes, data appears in Log Analytics.

**Health Monitor data:**
```kql
IPCHealthMonitor_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, deviceId_s, status_s, system_cpu_percent_d, system_memory_percent_d
| order by TimeGenerated desc
| take 10
```

**Security Audit data:**
```kql
IPCSecurityAudit_CL
| where TimeGenerated > ago(1h)
| summarize count() by EventID_d, EventType_s
| order by count_ desc
```

---

## Troubleshooting

### Pod CrashLoopBackOff

**Symptom:** Pod repeatedly restarts

**Check logs:**
```powershell
kubectl logs -n ipc-workloads -l app=health-monitor --previous
```

**Common causes:**
- Missing `azure-monitor-credentials` secret (pod runs but doesn't upload)
- Python import errors (check Dockerfile dependencies)
- Network connectivity to Log Analytics blocked

### No Data in Log Analytics

**Symptom:** Pods running but no data in workspace

**Verify credentials:**
```powershell
# Check secret exists
kubectl get secret azure-monitor-credentials -n ipc-workloads

# Check workspace ID matches
kubectl get secret azure-monitor-credentials -n ipc-workloads -o jsonpath='{.data.workspaceId}' | base64 -d
```

**Check connectivity:**
```powershell
# From within container
kubectl exec -it -n ipc-workloads deploy/health-monitor -- curl -I "https://<your-workspace-id>.ods.opinsights.azure.com"
```

**Verify Log-Type:**
Data appears in Log Analytics under custom tables: `IPCHealthMonitor_CL` and `IPCSecurityAudit_CL` (the `_CL` suffix is added automatically).

### Image Pull Errors

**Symptom:** `ErrImagePull` or `ImagePullBackOff`

**Verify ACR secret:**
```powershell
kubectl get secret acr-pull-secret -n ipc-workloads
```

**Recreate if missing:**
```powershell
$acrPassword = az acr credential show --name <your-acr-name> --query "passwords[0].value" -o tsv

kubectl create secret docker-registry acr-pull-secret `
  --namespace ipc-workloads `
  --docker-server=<your-acr-name>.azurecr.io `
  --docker-username=<your-acr-name> `
  --docker-password=$acrPassword
```

---

## Production Considerations

| PoC Approach | Production Approach |
|--------------|---------------------|
| Simulated Windows events | Azure Monitor Agent for real event collection |
| HTTP Data Collector API | Azure Monitor Ingestion API (newer) |
| Basic alerting via status field | Azure Monitor Alerts with action groups |
| Single workspace | Per-customer workspaces for data isolation |
| 60-second collection interval | Configurable per customer SLA |

---

## Related Pages

- [Azure Foundation](01-Azure-Foundation.md) — Log Analytics workspace setup
- [Compliance as a Service](09-Compliance-as-a-Service.md) — NIST 800-171 control mapping
- [DevOps Operations Center](10-DevOps-Operations-Center.md) — Azure Monitor dashboards
- [Quick Reference](A2-Quick-Reference.md) — KQL queries for monitoring
