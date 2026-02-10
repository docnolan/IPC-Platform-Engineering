# Analytics Workloads

This page documents the **Anomaly Detection** and **Test Data Collector** containerized workloads that provide edge intelligence and data archival capabilities.

---

## Overview

Both workloads demonstrate edge computing value: processing happens locally, only alerts and summaries go to the cloud, reducing bandwidth and enabling real-time response.

---

## Anomaly Detection

### Purpose

Runs statistical anomaly detection locally on sensor data. Only sends alerts to the cloud—not raw data. This reduces bandwidth costs and enables sub-second detection latency that cloud-based solutions cannot achieve.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  IPC                                                                        │
│                                                                             │
│  ┌─────────────────────┐      ┌───────────────────────────────────────────┐ │
│  │  OPC-UA Server      │      │  AKS Edge (Container)                     │ │
│  │  (Sensor Data)      │      │  ┌───────────────────────────────────┐    │ │
│  │  - Vibration        │──────►  │  Anomaly Detection                │    │ │
│  │  - Temperature      │      │  │  - Reads sensor values            │    │ │
│  │  - Pressure         │      │  │  - Maintains sliding window       │    │ │
│  │                     │      │  │  - Calculates z-scores            │    │ │
│  └─────────────────────┘      │  │  - Sends alerts (NOT raw data)    │────┼─► Azure IoT Hub
│                               │  └───────────────────────────────────┘    │ │  (Alerts Only)
│                               └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Detection Algorithm

The detector uses a sliding window statistical approach:

1. Maintains the last N samples per tag (default: 20)
2. Calculates mean and standard deviation of the window
3. Computes z-score: `z = |current_value - mean| / std_dev`
4. Flags as anomaly if z-score exceeds threshold (default: 2.5σ)

This approach is lightweight (no ML framework required) and effective for detecting sudden deviations from normal operating patterns.

### Monitored Tags

| Tag | Normal Range | Alert Condition |
|-----|--------------|-----------------|
| Vibration | 0.3 - 0.7 g | > 2.5σ from mean |
| Temperature | 67 - 77°F | > 2.5σ from mean |
| Pressure | 14.2 - 15.2 PSI | > 2.5σ from mean |

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/anomaly-detection/Dockerfile` |
| Python source | `docker/anomaly-detection/src/detector.py` |
| K8s deployment | `kubernetes/workloads/anomaly-detection/deployment.yaml` |

### Dockerfile

**Path:** `C:\Projects\IPC-Platform-Engineering\docker\anomaly-detection\Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir asyncua numpy azure-iot-device

COPY src/detector.py .

CMD ["python", "detector.py"]
```

### Python Source Code

**Path:** `C:\Projects\IPC-Platform-Engineering\docker\anomaly-detection\src\detector.py`

```python
"""
Edge Anomaly Detection
Uses simple statistical methods to detect anomalies in sensor data
In production, this could use pre-trained ML models (ONNX, TensorFlow Lite)
"""

import os
import asyncio
import json
import numpy as np
from datetime import datetime
from collections import deque
from asyncua import Client
from azure.iot.device import IoTHubDeviceClient, Message

# Configuration
OPCUA_ENDPOINT = os.getenv("OPCUA_ENDPOINT", "opc.tcp://opcua-simulator:4840/freeopcua/server/")
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
DEVICE_ID = os.getenv("HOSTNAME", "unknown-device")
DETECTION_INTERVAL = int(os.getenv("DETECTION_INTERVAL", "5"))
WINDOW_SIZE = int(os.getenv("WINDOW_SIZE", "20"))
ANOMALY_THRESHOLD = float(os.getenv("ANOMALY_THRESHOLD", "2.5"))  # Standard deviations

# Tags to monitor for anomalies
MONITORED_TAGS = [
    ("ns=2;s=ProductionLine/Vibration", "Vibration"),
    ("ns=2;s=ProductionLine/Temperature", "Temperature"),
    ("ns=2;s=ProductionLine/Pressure", "Pressure"),
]

class AnomalyDetector:
    def __init__(self, window_size=20, threshold=2.5):
        self.window_size = window_size
        self.threshold = threshold
        self.history = {}  # tag -> deque of values
    
    def add_sample(self, tag_name, value):
        """Add a sample and return anomaly status"""
        if tag_name not in self.history:
            self.history[tag_name] = deque(maxlen=self.window_size)
        
        self.history[tag_name].append(value)
        
        # Need enough samples for detection
        if len(self.history[tag_name]) < self.window_size // 2:
            return None, None, None
        
        values = np.array(self.history[tag_name])
        mean = np.mean(values)
        std = np.std(values)
        
        if std == 0:
            return False, 0, mean
        
        z_score = abs(value - mean) / std
        is_anomaly = z_score > self.threshold
        
        return is_anomaly, z_score, mean

async def main():
    print(f"Anomaly Detection starting for device: {DEVICE_ID}")
    print(f"OPC-UA Endpoint: {OPCUA_ENDPOINT}")
    print(f"Detection interval: {DETECTION_INTERVAL} seconds")
    print(f"Window size: {WINDOW_SIZE} samples")
    print(f"Anomaly threshold: {ANOMALY_THRESHOLD} standard deviations")
    
    detector = AnomalyDetector(window_size=WINDOW_SIZE, threshold=ANOMALY_THRESHOLD)
    
    # Connect to IoT Hub
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        iot_client = IoTHubDeviceClient.create_from_connection_string(IOT_HUB_CONNECTION_STRING)
        iot_client.connect()
        print("Connected to Azure IoT Hub")
    
    # Connect to OPC-UA
    opcua_client = Client(OPCUA_ENDPOINT)
    
    try:
        await opcua_client.connect()
        print(f"Connected to OPC-UA server")
        
        # Get nodes
        nodes = []
        for tag_path, tag_name in MONITORED_TAGS:
            try:
                node = opcua_client.get_node(tag_path)
                nodes.append((node, tag_name))
                print(f"  Monitoring: {tag_name}")
            except Exception as e:
                print(f"  Failed to monitor {tag_name}: {e}")
        
        anomaly_count = 0
        
        while True:
            timestamp = datetime.utcnow().isoformat() + "Z"
            anomalies_detected = []
            
            print(f"\n[{timestamp}] Checking for anomalies...")
            
            for node, tag_name in nodes:
                try:
                    value = await node.read_value()
                    is_anomaly, z_score, baseline = detector.add_sample(tag_name, value)
                    
                    if is_anomaly is None:
                        print(f"  {tag_name}: {value:.2f} (collecting baseline...)")
                    elif is_anomaly:
                        anomaly_count += 1
                        anomaly_info = {
                            "tag": tag_name,
                            "value": round(value, 3),
                            "baseline": round(baseline, 3),
                            "deviation": round(z_score, 2),
                            "threshold": ANOMALY_THRESHOLD
                        }
                        anomalies_detected.append(anomaly_info)
                        print(f"  WARNING  {tag_name}: {value:.2f} (ANOMALY! z={z_score:.2f}, baseline={baseline:.2f})")
                    else:
                        print(f"  ✓ {tag_name}: {value:.2f} (normal, z={z_score:.2f})")
                        
                except Exception as e:
                    print(f"  Error reading {tag_name}: {e}")
            
            # Send alert if anomalies detected
            if anomalies_detected and iot_client:
                alert = {
                    "messageType": "anomalyAlert",
                    "deviceId": DEVICE_ID,
                    "timestamp": timestamp,
                    "anomalyCount": len(anomalies_detected),
                    "totalAnomalies": anomaly_count,
                    "anomalies": anomalies_detected,
                    "severity": "warning" if len(anomalies_detected) < 2 else "critical"
                }
                message = Message(json.dumps(alert))
                message.content_type = "application/json"
                message.custom_properties["severity"] = alert["severity"]
                iot_client.send_message(message)
                print(f"  -> Alert sent to IoT Hub (severity: {alert['severity']})")
            
            await asyncio.sleep(DETECTION_INTERVAL)
            
    except Exception as e:
        print(f"Error: {e}")
    finally:
        await opcua_client.disconnect()
        if iot_client:
            iot_client.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
```

### Kubernetes Deployment

**Path:** `C:\Projects\IPC-Platform-Engineering\kubernetes\workloads\anomaly-detection\deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: anomaly-detection
  namespace: ipc-workloads
  labels:
    app: anomaly-detection
    component: analytics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: anomaly-detection
  template:
    metadata:
      labels:
        app: anomaly-detection
        component: analytics
    spec:
      containers:
        - name: anomaly-detection
          image: <your-acr-name>.azurecr.io/ipc/anomaly-detection:latest
          env:
            - name: OPCUA_ENDPOINT
              value: "opc.tcp://opcua-simulator.ipc-workloads.svc.cluster.local:4840/freeopcua/server/"
            - name: DETECTION_INTERVAL
              value: "5"
            - name: WINDOW_SIZE
              value: "20"
            - name: ANOMALY_THRESHOLD
              value: "2.5"
            - name: IOT_HUB_CONNECTION_STRING
              valueFrom:
                secretKeyRef:
                  name: iot-hub-connection
                  key: connectionString
                  optional: true
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "200m"
      imagePullSecrets:
        - name: acr-pull-secret
```

---

## Test Data Collector

### Purpose

Watches a local folder for test result files (CSV, JSON) and uploads them to Azure Blob Storage. Provides full traceability for automotive PPAP, FDA compliance, and defense contract requirements.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  IPC                                                                        │
│                                                                             │
│  ┌─────────────────────┐      ┌───────────────────────────────────────────┐ │
│  │  LabVIEW / .NET     │      │  AKS Edge (Container)                     │ │
│  │  Test Application   │      │  ┌───────────────────────────────────┐    │ │
│  │                     │      │  │  Test Data Collector              │    │ │
│  │  Writes CSV to:     │──────►  │  - Watches /data/test-results     │    │ │
│  │  C:\TestResults     │      │  │  - Parses CSV/JSON files          │    │ │
│  │  (mounted volume)   │      │  │  - Extracts test result/metadata  │    │ │
│  │                     │      │  │  - Uploads to Azure Blob          │────┼─► Azure Blob Storage
│  └─────────────────────┘      │  │  - Sends summary to IoT Hub       │────┼─► Azure IoT Hub
│                               │  └───────────────────────────────────┘    │ │
│                               └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Behavior

1. Watches `/data/test-results` directory for new files
2. Detects new CSV or JSON files via filesystem events
3. Parses content, extracts test result (PASS/FAIL)
4. Adds metadata (device ID, timestamp, file hash)
5. Uploads complete record to Azure Blob: `{deviceId}/{yyyy/MM/dd}/{filename}.json`
6. Sends summary to IoT Hub for dashboard tracking
7. Tracks processed files to avoid duplicates

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/test-data-collector/Dockerfile` |
| Python source | `docker/test-data-collector/src/collector.py` |
| K8s deployment | `kubernetes/workloads/test-data-collector/deployment.yaml` |

### Dockerfile

**Path:** `C:\Projects\IPC-Platform-Engineering\docker\test-data-collector\Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir watchdog azure-storage-blob azure-iot-device

COPY src/collector.py .

# Create watch directory
RUN mkdir -p /data/test-results

CMD ["python", "collector.py"]
```

### Python Source Code

**Path:** `C:\Projects\IPC-Platform-Engineering\docker\test-data-collector\src\collector.py`

```python
"""
Test Stand Data Collector
Watches for test result files and uploads to Azure
"""

import os
import json
import csv
import time
import hashlib
from datetime import datetime
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from azure.storage.blob import BlobServiceClient
from azure.iot.device import IoTHubDeviceClient, Message

# Configuration
WATCH_DIR = os.getenv("WATCH_DIR", "/data/test-results")
BLOB_CONNECTION_STRING = os.getenv("BLOB_CONNECTION_STRING", "")
BLOB_CONTAINER = os.getenv("BLOB_CONTAINER", "test-results")
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
DEVICE_ID = os.getenv("HOSTNAME", "unknown-device")

class TestResultHandler(FileSystemEventHandler):
    def __init__(self, blob_client, iot_client):
        self.blob_client = blob_client
        self.iot_client = iot_client
        self.processed_files = set()
    
    def on_created(self, event):
        if event.is_directory:
            return
        
        filepath = event.src_path
        filename = os.path.basename(filepath)
        
        # Only process CSV and JSON files
        if not filename.lower().endswith(('.csv', '.json')):
            return
        
        # Avoid duplicate processing
        file_hash = self._get_file_hash(filepath)
        if file_hash in self.processed_files:
            return
        
        print(f"New test result detected: {filename}")
        
        # Wait for file to be fully written
        time.sleep(1)
        
        try:
            # Parse the file
            test_data = self._parse_file(filepath)
            
            # Add metadata
            test_data["metadata"] = {
                "sourceFile": filename,
                "deviceId": DEVICE_ID,
                "uploadTimestamp": datetime.utcnow().isoformat() + "Z",
                "fileHash": file_hash
            }
            
            # Upload to Blob Storage
            blob_name = None
            if self.blob_client:
                blob_name = f"{DEVICE_ID}/{datetime.utcnow().strftime('%Y/%m/%d')}/{filename}.json"
                blob_client = self.blob_client.get_blob_client(container=BLOB_CONTAINER, blob=blob_name)
                blob_client.upload_blob(json.dumps(test_data, indent=2), overwrite=True)
                print(f"  -> Uploaded to Blob: {blob_name}")
            
            # Send summary to IoT Hub
            if self.iot_client:
                summary = {
                    "messageType": "testResult",
                    "deviceId": DEVICE_ID,
                    "timestamp": datetime.utcnow().isoformat() + "Z",
                    "testId": test_data.get("testId", filename),
                    "result": test_data.get("result", "UNKNOWN"),
                    "blobPath": blob_name if self.blob_client else None
                }
                message = Message(json.dumps(summary))
                message.content_type = "application/json"
                self.iot_client.send_message(message)
                print(f"  -> Sent summary to IoT Hub")
            
            self.processed_files.add(file_hash)
            print(f"  -> Processing complete")
            
        except Exception as e:
            print(f"  -> Error processing {filename}: {e}")
    
    def _get_file_hash(self, filepath):
        with open(filepath, 'rb') as f:
            return hashlib.md5(f.read()).hexdigest()
    
    def _parse_file(self, filepath):
        filename = os.path.basename(filepath).lower()
        
        if filename.endswith('.json'):
            with open(filepath, 'r') as f:
                return json.load(f)
        
        elif filename.endswith('.csv'):
            with open(filepath, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
                # Try to extract test result info
                result = {
                    "testId": os.path.splitext(os.path.basename(filepath))[0],
                    "recordCount": len(rows),
                    "data": rows
                }
                
                # Look for common result indicators
                for row in rows:
                    for key, value in row.items():
                        if 'result' in key.lower() or 'status' in key.lower():
                            result["result"] = value
                            break
                        if 'pass' in str(value).lower():
                            result["result"] = "PASS"
                        elif 'fail' in str(value).lower():
                            result["result"] = "FAIL"
                
                return result
        
        return {"raw": open(filepath, 'r').read()}

def main():
    print(f"Test Data Collector starting...")
    print(f"Watching directory: {WATCH_DIR}")
    print(f"Device ID: {DEVICE_ID}")
    
    # Initialize Azure clients
    blob_service = None
    if BLOB_CONNECTION_STRING:
        blob_service = BlobServiceClient.from_connection_string(BLOB_CONNECTION_STRING)
        print("Connected to Azure Blob Storage")
    else:
        print("Blob Storage not configured (no uploads)")
    
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        iot_client = IoTHubDeviceClient.create_from_connection_string(IOT_HUB_CONNECTION_STRING)
        iot_client.connect()
        print("Connected to Azure IoT Hub")
    else:
        print("IoT Hub not configured (no summaries)")
    
    # Ensure watch directory exists
    Path(WATCH_DIR).mkdir(parents=True, exist_ok=True)
    
    # Set up file watcher
    handler = TestResultHandler(blob_service, iot_client)
    observer = Observer()
    observer.schedule(handler, WATCH_DIR, recursive=False)
    observer.start()
    
    print(f"Watching for test results in {WATCH_DIR}...")
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    
    observer.join()
    if iot_client:
        iot_client.disconnect()

if __name__ == "__main__":
    main()
```

### Kubernetes Deployment

**Path:** `C:\Projects\IPC-Platform-Engineering\kubernetes\workloads\test-data-collector\deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-data-collector
  namespace: ipc-workloads
  labels:
    app: test-data-collector
    component: analytics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-data-collector
  template:
    metadata:
      labels:
        app: test-data-collector
        component: analytics
    spec:
      containers:
        - name: test-data-collector
          image: <your-acr-name>.azurecr.io/ipc/test-data-collector:latest
          env:
            - name: WATCH_DIR
              value: "/data/test-results"
            - name: BLOB_CONTAINER
              value: "test-results"
            - name: BLOB_CONNECTION_STRING
              valueFrom:
                secretKeyRef:
                  name: blob-storage-credentials
                  key: connectionString
                  optional: true
            - name: IOT_HUB_CONNECTION_STRING
              valueFrom:
                secretKeyRef:
                  name: iot-hub-connection
                  key: connectionString
                  optional: true
          volumeMounts:
            - name: test-results
              mountPath: /data/test-results
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"
      volumes:
        - name: test-results
          hostPath:
            path: /mnt/test-results
            type: DirectoryOrCreate
      imagePullSecrets:
        - name: acr-pull-secret
```

---

## Required Secrets

### IoT Hub Connection (shared with OPC-UA Gateway)

```powershell
# On the VM (IPC-Factory-01)

# Retrieve connection string
$connString = az iot hub device-identity connection-string show `
  --hub-name "<your-iothub-name>" `
  --device-id "ipc-factory-01" `
  --query connectionString -o tsv

# Create secret (if not already exists)
kubectl create secret generic iot-hub-connection `
  --namespace ipc-workloads `
  --from-literal=connectionString="$connString"
```

### Blob Storage Connection

```powershell
# Retrieve connection string
$blobConnString = az storage account show-connection-string `
  --name "stipcplatformXXXX" `
  --resource-group "rg-ipc-platform-monitoring" `
  --query connectionString -o tsv

# Create secret
kubectl create secret generic blob-storage-credentials `
  --namespace ipc-workloads `
  --from-literal=connectionString="$blobConnString"
```

---

## Build and Deploy

### Build Anomaly Detection

```powershell
az acr build --registry <your-acr-name> `
  --image ipc/anomaly-detection:latest `
  --file docker/anomaly-detection/Dockerfile `
  docker/anomaly-detection/
```

### Build Test Data Collector

```powershell
az acr build --registry <your-acr-name> `
  --image ipc/test-data-collector:latest `
  --file docker/test-data-collector/Dockerfile `
  docker/test-data-collector/
```

### Deploy via GitOps

1. Commit deployment manifests to `kubernetes/workloads/` directory
2. Push to Azure DevOps repository
3. Flux automatically syncs within 5 minutes

---

## Verification

### Check Pod Status

```powershell
kubectl get pods -n ipc-workloads -l component=analytics
```

Expected output:
```
NAME                                   READY   STATUS    RESTARTS   AGE
anomaly-detection-xxxxxxxxxx-xxxxx     1/1     Running   0          5m
test-data-collector-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
```

### View Anomaly Detection Logs

```powershell
kubectl logs -n ipc-workloads -l app=anomaly-detection --tail=30
```

Expected output:
```
Anomaly Detection starting for device: anomaly-detection-7f8b5c9d4-k2n3m
OPC-UA Endpoint: opc.tcp://opcua-simulator.ipc-workloads.svc.cluster.local:4840/freeopcua/server/
Detection interval: 5 seconds
Window size: 20 samples
Anomaly threshold: 2.5 standard deviations
Connected to Azure IoT Hub
Connected to OPC-UA server
  Monitoring: Vibration
  Monitoring: Temperature
  Monitoring: Pressure

[2026-01-23T16:00:00Z] Checking for anomalies...
  ✓ Vibration: 0.52 (normal, z=0.34)
  ✓ Temperature: 72.15 (normal, z=0.21)
  ✓ Pressure: 14.68 (normal, z=0.15)

[2026-01-23T16:00:05Z] Checking for anomalies...
  WARNING  Vibration: 3.45 (ANOMALY! z=4.12, baseline=0.51)
  ✓ Temperature: 72.30 (normal, z=0.28)
  ✓ Pressure: 14.71 (normal, z=0.19)
  -> Alert sent to IoT Hub (severity: warning)
```

### View Test Data Collector Logs

```powershell
kubectl logs -n ipc-workloads -l app=test-data-collector --tail=20
```

Expected output:
```
Test Data Collector starting...
Watching directory: /data/test-results
Device ID: test-data-collector-6c4d7b8e5-m4n5p
Connected to Azure Blob Storage
Connected to Azure IoT Hub
Watching for test results in /data/test-results...
```

### Test the Data Collector

Create a test file to verify the collector is working:

```powershell
# On the VM - create test file in the watched directory
# First, find the actual mount point
kubectl exec -it -n ipc-workloads deploy/test-data-collector -- ls -la /data/test-results

# Create a test CSV from the host
# The hostPath maps /mnt/test-results to the container's /data/test-results
sudo mkdir -p /mnt/test-results
echo "testId,measurement,result" | sudo tee /mnt/test-results/test001.csv
echo "T001,99.5,PASS" | sudo tee -a /mnt/test-results/test001.csv
```

Then check the logs:
```powershell
kubectl logs -n ipc-workloads -l app=test-data-collector --tail=10
```

---

## Monitoring Anomaly Alerts

### IoT Hub Query

View anomaly alerts in Azure Portal:

1. Navigate to IoT Hub → Message routing → Messages
2. Or use Azure CLI:

```powershell
# Monitor IoT Hub messages (requires IoT Hub extension)
az iot hub monitor-events --hub-name "<your-iothub-name>" --device-id "ipc-factory-01"
```

### KQL Query for Anomaly Summary

If routing anomaly alerts to Log Analytics:

```kql
// Anomaly alerts from IoT Hub (if routed to Log Analytics)
AzureDiagnostics
| where ResourceType == "IOTHUBS"
| where Category == "Routes"
| extend MessageBody = parse_json(body_s)
| where MessageBody.messageType == "anomalyAlert"
| project TimeGenerated, DeviceId = MessageBody.deviceId, Severity = MessageBody.severity, AnomalyCount = MessageBody.anomalyCount
| order by TimeGenerated desc
```

---

## Troubleshooting

### Anomaly Detection: Cannot Connect to OPC-UA

**Symptom:** Logs show connection errors to OPC-UA server

**Verify OPC-UA simulator is running:**
```powershell
kubectl get pods -n ipc-workloads -l app=opcua-simulator
```

**Check service DNS resolution:**
```powershell
kubectl exec -it -n dmc-workloads deploy/anomaly-detection -- nslookup opcua-simulator.dmc-workloads.svc.cluster.local
```

**Verify service exists:**
```powershell
kubectl get svc -n dmc-workloads opcua-simulator
```

### Test Data Collector: Files Not Detected

**Symptom:** Files placed in watch directory are not processed

**Check volume mount:**
```powershell
kubectl describe pod -n dmc-workloads -l app=test-data-collector | Select-String -A5 "Mounts:"
```

**Verify host directory exists:**
```powershell
# On the AKS Edge VM
ls -la /mnt/test-results
```

**Check file permissions:**
```powershell
kubectl exec -it -n dmc-workloads deploy/test-data-collector -- ls -la /data/test-results
```

### No Alerts Sent to IoT Hub

**Symptom:** Anomalies detected but no messages in IoT Hub

**Verify secret exists:**
```powershell
kubectl get secret iot-hub-connection -n dmc-workloads
```

**Check connection string format:**
The connection string should start with `HostName=<your-iothub-name>.azure-devices.net;DeviceId=...`

**Test IoT Hub connectivity:**
```powershell
# From container
kubectl exec -it -n dmc-workloads deploy/anomaly-detection -- curl -I "https://<your-iothub-name>.azure-devices.net"
```

---

## EV Battery Simulator

### Purpose

Simulates a 96-cell EV battery pack with high-frequency telemetry (2Hz default). Demonstrates IPC's capabilities in electric vehicle battery end-of-line test systems—their high-volume production scenario.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  AKS Edge (Container)                                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  EV Battery Simulator                                                 │  │
│  │  - Simulates 96 cell voltages (CAN-bus style data)                   │  │
│  │  - Charge/Discharge cycles with realistic SoC drain                  │  │
│  │  - Pack voltage, current, temperature telemetry                      │  │
│  │  - Test phases: IDLE → DISCHARGING → REST → CHARGING → IDLE          │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│                           Azure IoT Hub (ev_battery dataType)               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Features

| Feature | Description |
|---------|-------------|
| **High Cardinality** | 96 individual cell voltages per message |
| **High Frequency** | Configurable 2Hz default (500ms interval) |
| **State Machine** | Simulates charge/discharge test cycles |
| **Realistic Physics** | SoC, voltage curves, thermal behavior |

### Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `IOT_HUB_CONNECTION_STRING` | Azure IoT Hub connection | (required) |
| `PUBLISH_INTERVAL` | Seconds between messages | `0.5` |
| `DEVICE_ID` | Device identifier | `ev-battery-lab-01` |
| `NUM_CELLS` | Number of battery cells | `96` |

### Telemetry Schema

```json
{
  "timestamp": "2026-01-30T12:00:00Z",
  "deviceId": "ev-battery-lab-01",
  "dataType": "ev_battery",
  "pack": {
    "voltage": 384.5,
    "current": -150.0,
    "stateOfCharge": 75.2,
    "temperature": 32.1,
    "testPhase": "DISCHARGING",
    "cellMin": 3.95,
    "cellMax": 4.02,
    "cellDelta": 0.07
  },
  "cells": {
    "cell_01": 4.0123,
    "cell_02": 3.9876,
    "...": "..."
  }
}
```

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/ev-battery-simulator/Dockerfile` |
| Python source | `docker/ev-battery-simulator/src/simulator.py` |
| K8s deployment | `kubernetes/workloads/ev-battery-simulator/deployment.yaml` |

### Health Endpoint

- **Port:** 8080
- **Path:** `/health`
- **Liveness Probe:** Configured

---

## Vision Simulator

### Purpose

Simulates a machine vision quality inspection station. Generates event-based (bursty) inspection results with PASS/FAIL outcomes, defect classification, and statistical tracking. Demonstrates IPC's machine vision integration capabilities.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  AKS Edge (Container)                                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  Vision Inspection Station                                            │  │
│  │  - Simulates 3-camera inspection system                              │  │
│  │  - Generates PASS/FAIL with configurable rate (default 95%)          │  │
│  │  - Tracks defect types: Scratch, Dent, Discoloration, etc.           │  │
│  │  - Batch tracking with part serial numbers                           │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│                           Azure IoT Hub (vision_inspection dataType)        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Features

| Feature | Description |
|---------|-------------|
| **Event-Based** | Bursty data pattern (one message per inspection) |
| **Quality Metrics** | Pass rate, defect distribution tracking |
| **Multi-Camera** | Simulates 3-camera system with timing data |
| **Batch Tracking** | Automatic batch rollover with IDs |

### Defect Types

| Defect | Probability |
|--------|-------------|
| Scratch | 45% |
| Dent | 25% |
| Discoloration | 15% |
| Contamination | 10% |
| Dimensional | 5% |

### Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `IOT_HUB_CONNECTION_STRING` | Azure IoT Hub connection | (required) |
| `INSPECTION_INTERVAL` | Seconds between inspections | `5` |
| `DEVICE_ID` | Station identifier | `vision-station-04` |
| `PASS_RATE` | Target pass rate | `0.95` |

### Telemetry Schema

```json
{
  "timestamp": "2026-01-30T12:00:00Z",
  "deviceId": "vision-station-04",
  "dataType": "vision_inspection",
  "inspection": {
    "id": "INS-20260130120000-000001",
    "batchId": "A1B2C3D4",
    "partType": "Housing-A1",
    "partSerial": "Housing-A1-123456",
    "result": "FAIL",
    "defectType": "Scratch",
    "processTimeMs": 156,
    "confidence": 0.973
  },
  "cameras": [
    {"cameraId": "CAM-01", "position": "Top", "captureTimeMs": 22}
  ],
  "defects": [
    {"type": "Scratch", "severity": "Minor", "location": {"x": 450, "y": 230}}
  ],
  "statistics": {
    "totalInspections": 1000,
    "passRate": 94.8
  }
}
```

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/vision-simulator/Dockerfile` |
| Python source | `docker/vision-simulator/src/simulator.py` |
| K8s deployment | `kubernetes/workloads/vision-simulator/deployment.yaml` |

---

## Motion Simulator

### Purpose

Simulates a 3-axis servo gantry system via OPC-UA protocol. Provides real-time correlated position data (X, Y, Z) with motion patterns, temperature monitoring, and fan control. Demonstrates CNC/robotics monitoring use cases.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  AKS Edge (Container)                                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  Motion/Gantry OPC-UA Server (Port 4841)                              │  │
│  │  - 3-axis position and velocity (X, Y, Z)                            │  │
│  │  - Motion patterns: CIRCLE, PICK_PLACE                               │  │
│  │  - Motor temperature with fan control hysteresis                     │  │
│  │  - Servo status, alarm states, cycle counting                        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                          OPC-UA Protocol │                                  │
│                                          ▼                                  │
│                                  Motion Gateway                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### OPC-UA Tags

| Tag | Description | Unit |
|-----|-------------|------|
| `Axis_X_Pos` | X-axis position | mm |
| `Axis_Y_Pos` | Y-axis position | mm |
| `Axis_Z_Pos` | Z-axis position | mm |
| `Axis_X_Vel` | X-axis velocity | mm/s |
| `Axis_Y_Vel` | Y-axis velocity | mm/s |
| `Axis_Z_Vel` | Z-axis velocity | mm/s |
| `Motor_Temp` | Motor temperature | °C |
| `Fan_Status` | Cooling fan state | Boolean |
| `Servo_Enabled` | Servo power state | Boolean |
| `In_Motion` | Motion status | Boolean |
| `Alarm_Active` | Overtemp alarm | Boolean |
| `Cycle_Count` | Completed cycles | Integer |
| `Motion_Mode` | Current pattern | String |

### Motion Patterns

| Pattern | Description | Duration |
|---------|-------------|----------|
| CIRCLE | Continuous circular motion | 30s |
| PICK_PLACE | 4-phase pick and place cycle | 30s |

### Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `OPCUA_PORT` | OPC-UA server port | `4841` |
| `HEALTH_PORT` | Health endpoint port | `8080` |
| `UPDATE_INTERVAL` | Simulation update rate | `0.1` (10Hz) |

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/motion-simulator/Dockerfile` |
| Python source | `docker/motion-simulator/src/simulator.py` |
| K8s deployment | `kubernetes/workloads/motion-simulator/deployment.yaml` |

---

## Motion Gateway

### Purpose

Reads motion data from the Motion Simulator's OPC-UA server and forwards to Azure IoT Hub. Follows the same gateway pattern as the OPC-UA Gateway but specialized for motion/gantry data.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Motion Simulator                        Motion Gateway                     │
│  (OPC-UA Server)          OPC-UA         (Container)                        │
│  ┌──────────────────┐    Protocol    ┌────────────────────────────────────┐ │
│  │ Port 4841        │◄──────────────►│ - Connects to motion-simulator     │ │
│  │ GantryB namespace│                │ - Reads all axis position/velocity  │ │
│  └──────────────────┘                │ - Reads motor temp, fan, alarms     │ │
│                                      │ - Sends to IoT Hub every 1s         │ │
│                                      └────────────────────────────────────┘ │
│                                                          │                  │
│                                                          ▼                  │
│                                               Azure IoT Hub                 │
│                                          (motion_gantry dataType)           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `OPCUA_ENDPOINT` | Motion simulator OPC-UA URL | `opc.tcp://motion-simulator:4841/freeopcua/server/` |
| `IOT_HUB_CONNECTION_STRING` | Azure IoT Hub connection | (required) |
| `PUBLISH_INTERVAL` | Seconds between publishes | `1` |
| `DEVICE_ID` | Device identifier | `gantry-b` |

### Telemetry Schema

```json
{
  "timestamp": "2026-01-30T12:00:00Z",
  "deviceId": "gantry-b",
  "dataType": "motion_gantry",
  "position": {
    "Axis_X_Pos": 85.234,
    "Axis_Y_Pos": 42.567,
    "Axis_Z_Pos": 55.123
  },
  "velocity": {
    "Axis_X_Vel": 150.2,
    "Axis_Y_Vel": 125.8,
    "Axis_Z_Vel": 75.3
  },
  "status": {
    "Motor_Temp": 38.5,
    "Fan_Status": true,
    "Servo_Enabled": true,
    "In_Motion": true,
    "Alarm_Active": false,
    "Cycle_Count": 42,
    "Motion_Mode": "PICK_PLACE"
  }
}
```

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/motion-gateway/Dockerfile` |
| Python source | `docker/motion-gateway/src/gateway.py` |
| K8s deployment | `kubernetes/workloads/motion-gateway/deployment.yaml` |

### Dependencies

The motion-gateway requires the motion-simulator to be running. Kubernetes service discovery handles the connection:

```yaml
# Deployment connects to:
# opc.tcp://motion-simulator.dmc-workloads.svc.cluster.local:4841/freeopcua/server/
```

---

## Production Considerations

| PoC Approach | Production Approach |
|--------------|---------------------|
| Statistical z-score detection | Pre-trained ONNX or TensorFlow Lite models |
| Single threshold for all tags | Per-tag configurable thresholds |
| Simple file watcher | Integration with test software APIs |
| MD5 hash deduplication | Database-backed file tracking |
| Single blob container | Per-customer containers with SAS tokens |

---

## Related Pages

- [OPC-UA Workloads](05-Workloads-OPC-UA.md) — Simulator provides data for anomaly detection
- [Monitoring Workloads](06-Workloads-Monitoring.md) — Health and compliance monitoring
- [Compliance as a Service](09-Compliance-as-a-Service.md) — Test data retention requirements
- [Demo Script](11-Demo-Script.md) — How to trigger anomalies for demo
