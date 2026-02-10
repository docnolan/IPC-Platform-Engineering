# Workloads: OPC-UA Gateway and Data Simulators
# Production Gateway and PoC Data Generators

---

# Table of Contents

1. [Overview](#1-overview)
2. [Production Workload: OPC-UA Gateway](#2-production-workload-opc-ua-gateway)
3. [PoC Simulators Overview](#3-poc-simulators-overview)
4. [Simulator: OPC-UA (Generic PLC)](#4-simulator-opc-ua-generic-plc)
5. [Simulator: EV Battery Pack](#5-simulator-ev-battery-pack)
6. [Simulator: Vision Inspection](#6-simulator-vision-inspection)
7. [Simulator: Motion/Gantry](#7-simulator-motiongantry)
8. [Build and Deploy](#8-build-and-deploy)
9. [Verification](#9-verification)
10. [Troubleshooting](#10-troubleshooting)

---

# 1. Overview

This document covers two categories of workloads:

| Category | Workloads | Purpose | Ships to Customer? |
|----------|-----------|---------|-------------------|
| **Production** | OPC-UA Gateway | Connects real PLCs to Azure IoT Hub | ✅ Yes |
| **PoC Simulators** | OPC-UA Simulator, EV Battery, Vision, Motion | Generate demo data for the PoC | ❌ No |

## 1.1 Why Multiple Simulators?

IPC's customers generate diverse industrial data patterns:

| Data Pattern | Example Use Case | Simulator |
|--------------|------------------|-----------|
| Time-series tags | Generic PLC monitoring | OPC-UA Simulator |
| High-speed, high-cardinality | Battery test systems (96+ cells) | EV Battery Simulator |
| Event-based discrete | Quality inspection stations | Vision Simulator |
| Real-time correlated state | Servo gantries, robotics | Motion Simulator |

The simulators prove the platform handles **all** of these patterns—not just generic OPC-UA tags. In production, these simulators are replaced by actual equipment.



# 2. Production Workload: OPC-UA Gateway

The OPC-UA Gateway is the **production-ready workload** that ships with customer panels. It connects to real OPC-UA servers and forwards data to Azure IoT Hub.

## 2.1 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  IPC                                                                            │
│  ┌─────────────────────┐      ┌───────────────────────────────────────────────┐ │
│  │  KEPServerEX        │      │  AKS Edge (Container)                         │ │
│  │  (OPC-UA Server)    │◄────►│  ┌─────────────────────────────────────────┐  │ │
│  │  Port 4840          │      │  │  OPC-UA Gateway                         │  │ │
│  └─────────────────────┘      │  │  - Subscribes to tags                   │  │ │
│                               │  │  - Converts to JSON                     │  │ │
│                               │  │  - Publishes to IoT Hub                 │──┼─┼──► Azure IoT Hub
│                               │  └─────────────────────────────────────────┘  │ │
│                               └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 2.2 Data Flow

1. **Real OPC-UA Server** (KEPServerEX, RSLinx, Siemens native) exposes PLC tags
2. **OPC-UA Gateway** connects and subscribes to configured tags
3. Gateway reads tag values at configured interval
4. Gateway publishes JSON telemetry to **Azure IoT Hub**
5. Data flows to Time Series Insights, Power BI, or custom dashboards

## 2.3 Dockerfile

**File:** `docker/opcua-gateway/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Upgrade system packages to fix vulnerabilities (e.g. CVE-2025-15467 in openssl)
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir asyncua azure-iot-device python-dotenv

COPY src/gateway.py .

# Security Hardening
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

CMD ["python", "gateway.py"]

USER 1000
```

## 2.4 Python Source Code

**File:** `docker/opcua-gateway/src/gateway.py`

```python
"""
OPC-UA to Azure IoT Hub Gateway
Subscribes to OPC-UA tags and publishes to IoT Hub
Features:
- Structured JSON Logging
- Health Check Server (/health)
"""

import asyncio
import json
import os
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from asyncua import Client
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message

# Configuration from environment variables
OPCUA_ENDPOINT = os.getenv("OPCUA_ENDPOINT", "opc.tcp://opcua-simulator:4840/freeopcua/server/")
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
PUBLISH_INTERVAL = int(os.getenv("PUBLISH_INTERVAL", "5"))
HEALTH_PORT = 8080

# Tags to subscribe to (could be loaded from ConfigMap)
TAGS = [
    "ns=2;s=ProductionLine/CycleCount",
    "ns=2;s=ProductionLine/PartsGood",
    "ns=2;s=ProductionLine/PartsBad",
    "ns=2;s=ProductionLine/Temperature",
    "ns=2;s=ProductionLine/Pressure",
    "ns=2;s=ProductionLine/Vibration",
    "ns=2;s=ProductionLine/MachineState",
]

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="OPCUAGateway", **kwargs):
    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "level": level,
        "component": component,
        "message": message,
        **kwargs
    }
    print(json.dumps(entry), flush=True)

# --- Op Maturity: Health Server ---
class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

def start_health_server():
    try:
        server = HTTPServer(('0.0.0.0', HEALTH_PORT), HealthHandler)
        log_json("INFO", f"Health server listening on port {HEALTH_PORT}", "HealthCheck")
        server.serve_forever()
    except Exception as e:
        log_json("ERROR", f"Failed to start health server: {e}", "HealthCheck")

async def main():
    # Start Health Server
    threading.Thread(target=start_health_server, daemon=True).start()

    log_json("INFO", "OPC-UA Gateway starting...", "Gateway")
    log_json("INFO", f"OPC-UA Endpoint: {OPCUA_ENDPOINT}")
    log_json("INFO", f"Publish Interval: {PUBLISH_INTERVAL} seconds")
    
    # Connect to IoT Hub
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        iot_client = IoTHubDeviceClient.create_from_connection_string(IOT_HUB_CONNECTION_STRING)
        await iot_client.connect()
        log_json("INFO", "Connected to Azure IoT Hub", "IoTHub")
    else:
        log_json("WARNING", "No IoT Hub connection string. Running in local-only mode.", "IoTHub")
    
    # Connect to OPC-UA server
    opcua_client = Client(OPCUA_ENDPOINT)
    
    try:
        await opcua_client.connect()
        log_json("INFO", f"Connected to OPC-UA server: {OPCUA_ENDPOINT}", "OPCUA")
        
        # Get tag nodes
        nodes = []
        for tag in TAGS:
            try:
                node = opcua_client.get_node(tag)
                nodes.append((tag, node))
                log_json("INFO", f"Subscribed to: {tag}", "OPCUA")
            except Exception as e:
                log_json("ERROR", f"Failed to subscribe to {tag}: {e}", "OPCUA")
        
        # Main loop - read and publish
        while True:
            telemetry = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "deviceId": os.getenv("HOSTNAME", "unknown"),
                "tags": {}
            }
            
            for tag_path, node in nodes:
                try:
                    value = await node.read_value()
                    tag_name = tag_path.split("/")[-1]
                    telemetry["tags"][tag_name] = value
                except Exception as e:
                    log_json("ERROR", f"Error reading {tag_path}: {e}", "OPCUA")
            
            # Log locally
            log_json("INFO", f"Telemetry collected", "Telemetry", data_preview=str(telemetry["tags"]))
            
            # Send to IoT Hub
            if iot_client:
                message = Message(json.dumps(telemetry))
                message.content_type = "application/json"
                message.content_encoding = "utf-8"
                await iot_client.send_message(message)
                log_json("INFO", "Sent to IoT Hub", "IoTHub")
            
            await asyncio.sleep(PUBLISH_INTERVAL)
            
    except Exception as e:
        log_json("ERROR", f"Fatal Error: {e}", "System")
    finally:
        try:
            await opcua_client.disconnect()
        except:
             pass
        if iot_client:
             try:
                 await iot_client.disconnect()
             except:
                 pass

if __name__ == "__main__":
    asyncio.run(main())
```

## 2.5 Configuration Options

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `OPCUA_ENDPOINT` | `opc.tcp://opcua-simulator:4840/freeopcua/server/` | OPC-UA server URL |
| `IOT_HUB_CONNECTION_STRING` | (empty) | Azure IoT Hub device connection string |
| `PUBLISH_INTERVAL` | `5` | Seconds between telemetry publishes |

## 2.6 Kubernetes Deployment

**File:** `kubernetes/workloads/opcua-gateway/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opcua-gateway
  namespace: ipc-workloads
  labels:
    app.kubernetes.io/name: opcua-gateway
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/managed-by: Flux
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: opcua-gateway
  template:
    metadata:
      labels:
        app.kubernetes.io/name: opcua-gateway
        app.kubernetes.io/version: "1.0.0"
        app.kubernetes.io/managed-by: Flux
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: opcua-gateway
          image: <your-acr-name>.azurecr.io/ipc/opcua-gateway:v1.0.0
          imagePullPolicy: Always
          securityContext:
            runAsUser: 1000
            runAsGroup: 3000
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
          env:
            - name: OPCUA_ENDPOINT
              value: "opc.tcp://opcua-simulator.ipc-workloads.svc.cluster.local:4840/freeopcua/server/"
            - name: PUBLISH_INTERVAL
              value: "5"
            - name: IOT_HUB_CONNECTION_STRING
              valueFrom:
                secretKeyRef:
                  name: iot-hub-connection
                  key: connectionString
                  optional: true
          ports:
            - containerPort: 8080
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 2
            periodSeconds: 5
          volumeMounts:
            - name: tmp-volume
              mountPath: /tmp
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "200m"
      volumes:
        - name: tmp-volume
          emptyDir: {}
```

**File:** `kubernetes/workloads/opcua-gateway/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
```

## 2.7 Create IoT Hub Connection Secret

```powershell
# Get the device connection string
$CONNECTION_STRING = az iot hub device-identity connection-string show `
  --hub-name "<your-iothub-name>" `
  --device-id "ipc-factory-01" `
  --query connectionString -o tsv

# Create the secret on the cluster
kubectl create secret generic iot-hub-connection `
  --namespace ipc-workloads `
  --from-literal=connectionString="$CONNECTION_STRING"
```

---

# 3. PoC Simulators Overview

> **⚠️ IMPORTANT:** The simulators in this section are for **demonstration purposes only**. They are not intended for production deployment. In production, these would be replaced by actual industrial equipment (PLCs, test systems, vision cameras, servo drives).

## 3.1 Simulator Summary

| Simulator | Data Pattern | Frequency | Business Line |
|-----------|--------------|-----------|-------------------|
| OPC-UA Simulator | Generic PLC tags | 1 Hz | General automation |
| EV Battery Simulator | 96 cell voltages + pack metrics | 2 Hz | Battery Test Systems |
| Vision Simulator | PASS/FAIL inspection events | Every 5 sec | Machine Vision |
| Motion Simulator | 3-axis position via OPC-UA | 10 Hz | Robotics & Motion |

## 3.2 Simulator Use Cases

These simulators cover distinct technical patterns found in industrial environments:

- **EV Battery**: High-frequency, high-cardinality telemetry (96+ channels @ 10Hz).
- **Vision Inspection**: Event-based data with binary pass/fail outcomes.
- **Motion/Gantry**: Real-time position control data.

---

# 4. Simulator: OPC-UA (Generic PLC)

This simulator creates a generic OPC-UA server with typical production line and test stand tags.

## 4.1 Dockerfile

**File:** `docker/opcua-simulator/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir asyncua

COPY src/simulator.py .

EXPOSE 4840

CMD ["python", "simulator.py"]
```

## 4.2 Python Source Code

**File:** `docker/opcua-simulator/src/simulator.py`

```python
"""
OPC-UA Simulator for IPC Platform PoC
Simulates a PLC with typical industrial tags
"""

import asyncio
import random
import math
from datetime import datetime
from asyncua import Server, ua

async def main():
    server = Server()
    await server.init()
    
    server.set_endpoint("opc.tcp://0.0.0.0:4840/freeopcua/server/")
    server.set_server_name("IPC Simulated PLC")
    
    # Setup namespace
    uri = "http://ipc-platform.com/opcua/simulator"
    idx = await server.register_namespace(uri)
    
    # Create objects folder structure (like a real PLC)
    objects = server.nodes.objects
    
    # Production Line object
    production_line = await objects.add_object(idx, "ProductionLine")
    
    # Add simulated tags
    cycle_count = await production_line.add_variable(idx, "CycleCount", 0)
    await cycle_count.set_writable()
    
    parts_good = await production_line.add_variable(idx, "PartsGood", 0)
    await parts_good.set_writable()
    
    parts_bad = await production_line.add_variable(idx, "PartsBad", 0)
    await parts_bad.set_writable()
    
    machine_state = await production_line.add_variable(idx, "MachineState", "Running")
    await machine_state.set_writable()
    
    temperature = await production_line.add_variable(idx, "Temperature", 72.0)
    await temperature.set_writable()
    
    pressure = await production_line.add_variable(idx, "Pressure", 14.7)
    await pressure.set_writable()
    
    vibration = await production_line.add_variable(idx, "Vibration", 0.5)
    await vibration.set_writable()
    
    # Test Stand object
    test_stand = await objects.add_object(idx, "TestStand")
    
    test_running = await test_stand.add_variable(idx, "TestRunning", False)
    await test_running.set_writable()
    
    test_result = await test_stand.add_variable(idx, "LastTestResult", "PASS")
    await test_result.set_writable()
    
    test_value = await test_stand.add_variable(idx, "TestMeasurement", 0.0)
    await test_value.set_writable()
    
    print(f"OPC-UA Simulator started at opc.tcp://0.0.0.0:4840")
    print(f"Namespace: {uri}")
    print("Available tags:")
    print("  - ProductionLine/CycleCount")
    print("  - ProductionLine/PartsGood")
    print("  - ProductionLine/PartsBad")
    print("  - ProductionLine/MachineState")
    print("  - ProductionLine/Temperature")
    print("  - ProductionLine/Pressure")
    print("  - ProductionLine/Vibration")
    print("  - TestStand/TestRunning")
    print("  - TestStand/LastTestResult")
    print("  - TestStand/TestMeasurement")
    
    async with server:
        cycle = 0
        while True:
            await asyncio.sleep(1)
            cycle += 1
            
            # Simulate production line
            await cycle_count.write_value(cycle)
            
            # Occasionally produce parts
            if cycle % 5 == 0:
                if random.random() > 0.05:  # 95% yield
                    current_good = await parts_good.read_value()
                    await parts_good.write_value(current_good + 1)
                else:
                    current_bad = await parts_bad.read_value()
                    await parts_bad.write_value(current_bad + 1)
            
            # Simulate temperature fluctuation
            base_temp = 72.0
            temp_variation = math.sin(cycle / 30) * 5 + random.uniform(-1, 1)
            await temperature.write_value(round(base_temp + temp_variation, 2))
            
            # Simulate pressure
            base_pressure = 14.7
            pressure_variation = math.sin(cycle / 60) * 0.5 + random.uniform(-0.1, 0.1)
            await pressure.write_value(round(base_pressure + pressure_variation, 2))
            
            # Simulate vibration (with occasional spikes for anomaly detection demo)
            base_vibration = 0.5
            if random.random() > 0.98:  # 2% chance of spike
                await vibration.write_value(round(random.uniform(2.0, 5.0), 2))
            else:
                await vibration.write_value(round(base_vibration + random.uniform(-0.2, 0.2), 2))
            
            # Simulate test stand (run a test every 30 seconds)
            if cycle % 30 == 0:
                await test_running.write_value(True)
                await test_value.write_value(round(random.uniform(99.0, 101.0), 3))
                await asyncio.sleep(2)
                await test_running.write_value(False)
                result = "PASS" if 99.5 <= await test_value.read_value() <= 100.5 else "FAIL"
                await test_result.write_value(result)

if __name__ == "__main__":
    asyncio.run(main())
```

## 4.3 Simulated Tags

| Object | Tag Name | Type | Description |
|--------|----------|------|-------------|
| ProductionLine | CycleCount | Int | Total machine cycles |
| ProductionLine | PartsGood | Int | Good parts produced |
| ProductionLine | PartsBad | Int | Rejected parts |
| ProductionLine | MachineState | String | Running/Stopped/Faulted |
| ProductionLine | Temperature | Float | Process temperature (°F) |
| ProductionLine | Pressure | Float | Process pressure (PSI) |
| ProductionLine | Vibration | Float | Vibration level (mm/s) |
| TestStand | TestRunning | Bool | Test in progress |
| TestStand | LastTestResult | String | PASS/FAIL |
| TestStand | TestMeasurement | Float | Test measurement value |

## 4.4 Kubernetes Deployment

**File:** `kubernetes/workloads/opcua-simulator/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opcua-simulator
  namespace: ipc-workloads
  labels:
    app: opcua-simulator
    workload-type: simulator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opcua-simulator
  template:
    metadata:
      labels:
        app: opcua-simulator
        workload-type: simulator
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: opcua-simulator
          image: <your-acr-name>.azurecr.io/ipc/opcua-simulator:latest
          ports:
            - containerPort: 4840
              protocol: TCP
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: opcua-simulator
  namespace: ipc-workloads
spec:
  selector:
    app: opcua-simulator
  ports:
    - port: 4840
      targetPort: 4840
      protocol: TCP
  type: ClusterIP
```

**File:** `kubernetes/workloads/opcua-simulator/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
```

---

# 5. Simulator: EV Battery Pack

This simulator generates high-speed, high-cardinality data representing a 96-cell EV battery pack during charge/discharge testing. It demonstrates the platform's ability to handle thousands of data points per second.

## 5.1 Business Context

IPC builds battery end-of-line test systems. This simulator replicates the data pattern from those systems:
- 96 individual cell voltages
- Pack-level metrics (total voltage, current, temperature)
- State of charge tracking during test cycles

**Reference:** [IPC Battery Production Tester](https://www.ipc-platform.com/our-work/electric-vehicle-pack-end-of-line-test-with-ipcs-battery-production-tester/)

## 5.2 Dockerfile

**File:** `docker/ev-battery-simulator/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir azure-iot-device

COPY src/simulator.py .

CMD ["python", "-u", "simulator.py"]
```

## 5.3 Python Source Code

**File:** `docker/ev-battery-simulator/src/simulator.py`

```python
"""
EV Battery Pack Simulator for IPC Platform PoC
Simulates high-speed battery monitoring system (CAN bus style data)

This demonstrates:
- High-cardinality metrics (96 cell voltages)
- High-frequency updates (configurable, default 2Hz for demo)
- Slowly changing state (State of Charge draining)

Business Context: IPC builds EV battery end-of-line test systems.
This is their high-volume production test system.
"""

import asyncio
import json
import os
import random
import math
from datetime import datetime
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message

# Configuration
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
PUBLISH_INTERVAL = float(os.getenv("PUBLISH_INTERVAL", "0.5"))  # 2Hz default
DEVICE_ID = os.getenv("DEVICE_ID", "ev-battery-lab-01")
NUM_CELLS = int(os.getenv("NUM_CELLS", "96"))

# Simulation state
class BatteryPackState:
    def __init__(self, num_cells: int):
        self.num_cells = num_cells
        self.state_of_charge = 100.0  # Starts full
        self.pack_voltage = 400.0  # Nominal 400V pack
        self.pack_current = 0.0
        self.pack_temp = 25.0
        self.cycle_count = 0
        
        # Cell voltages - slight variance around nominal
        self.cell_voltages = [
            3.7 + random.uniform(-0.05, 0.05) 
            for _ in range(num_cells)
        ]
        
        # Discharge rate (% per second at full load)
        self.discharge_rate = 0.02
        
        # Simulate a test cycle
        self.test_phase = "IDLE"  # IDLE, CHARGING, DISCHARGING, REST
        self.phase_timer = 0
        
    def update(self, dt: float):
        """Update battery state based on elapsed time"""
        self.cycle_count += 1
        self.phase_timer += dt
        
        # Cycle through test phases
        if self.test_phase == "IDLE" and self.phase_timer > 5:
            self.test_phase = "DISCHARGING"
            self.phase_timer = 0
            print(f"[Phase] Starting DISCHARGE test")
            
        elif self.test_phase == "DISCHARGING":
            # Discharge at constant current
            self.pack_current = -150.0  # 150A discharge
            self.state_of_charge -= self.discharge_rate * dt * 10
            self.pack_temp += 0.01 * dt  # Slight heating
            
            if self.state_of_charge <= 20.0:
                self.test_phase = "REST"
                self.phase_timer = 0
                print(f"[Phase] Discharge complete, entering REST")
                
        elif self.test_phase == "REST" and self.phase_timer > 10:
            self.test_phase = "CHARGING"
            self.phase_timer = 0
            print(f"[Phase] Starting CHARGE cycle")
            
        elif self.test_phase == "CHARGING":
            # Charge at constant current
            self.pack_current = 75.0  # 75A charge
            self.state_of_charge += self.discharge_rate * dt * 5
            self.pack_temp -= 0.005 * dt  # Slight cooling
            
            if self.state_of_charge >= 95.0:
                self.test_phase = "IDLE"
                self.phase_timer = 0
                print(f"[Phase] Charge complete, entering IDLE")
                
        elif self.test_phase == "IDLE":
            self.pack_current = 0.0
            
        # Keep SoC in bounds
        self.state_of_charge = max(0.0, min(100.0, self.state_of_charge))
        
        # Update pack voltage based on SoC
        # Simplified: 3.0V (empty) to 4.2V (full) per cell
        cell_voltage_base = 3.0 + (self.state_of_charge / 100.0) * 1.2
        
        # Update individual cell voltages with realistic variance
        for i in range(self.num_cells):
            # Each cell drifts slightly
            drift = random.gauss(0, 0.002)
            self.cell_voltages[i] = cell_voltage_base + drift
            # Clamp to realistic range
            self.cell_voltages[i] = max(2.8, min(4.25, self.cell_voltages[i]))
        
        # Pack voltage is sum of cells
        self.pack_voltage = sum(self.cell_voltages)
        
        # Temperature bounds
        self.pack_temp = max(20.0, min(45.0, self.pack_temp))
        
    def to_telemetry(self) -> dict:
        """Generate telemetry message"""
        telemetry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "deviceId": DEVICE_ID,
            "dataType": "ev_battery",
            "pack": {
                "voltage": round(self.pack_voltage, 2),
                "current": round(self.pack_current, 2),
                "stateOfCharge": round(self.state_of_charge, 1),
                "temperature": round(self.pack_temp, 1),
                "testPhase": self.test_phase,
                "cycleCount": self.cycle_count
            },
            "cells": {}
        }
        
        # Add individual cell voltages
        for i, voltage in enumerate(self.cell_voltages):
            telemetry["cells"][f"cell_{i+1:02d}"] = round(voltage, 4)
            
        # Add derived metrics
        telemetry["pack"]["cellMin"] = round(min(self.cell_voltages), 4)
        telemetry["pack"]["cellMax"] = round(max(self.cell_voltages), 4)
        telemetry["pack"]["cellDelta"] = round(
            max(self.cell_voltages) - min(self.cell_voltages), 4
        )
        
        return telemetry


async def main():
    print("=" * 60)
    print("EV Battery Pack Simulator")
    print("=" * 60)
    print(f"Device ID: {DEVICE_ID}")
    print(f"Number of cells: {NUM_CELLS}")
    print(f"Publish interval: {PUBLISH_INTERVAL}s ({1/PUBLISH_INTERVAL:.1f} Hz)")
    print()
    
    # Initialize battery state
    battery = BatteryPackState(NUM_CELLS)
    
    # Connect to IoT Hub
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        try:
            iot_client = IoTHubDeviceClient.create_from_connection_string(
                IOT_HUB_CONNECTION_STRING
            )
            await iot_client.connect()
            print("[IoT Hub] Connected successfully")
        except Exception as e:
            print(f"[IoT Hub] Connection failed: {e}")
            print("[IoT Hub] Running in local-only mode")
            iot_client = None
    else:
        print("[IoT Hub] No connection string provided")
        print("[IoT Hub] Running in local-only mode")
    
    print()
    print("Starting simulation...")
    print("-" * 60)
    
    try:
        message_count = 0
        while True:
            # Update battery state
            battery.update(PUBLISH_INTERVAL)
            
            # Generate telemetry
            telemetry = battery.to_telemetry()
            message_count += 1
            
            # Log summary (not full payload - too large)
            if message_count % 10 == 0:  # Log every 10th message
                print(
                    f"[{telemetry['timestamp']}] "
                    f"Pack: {telemetry['pack']['voltage']:.1f}V, "
                    f"{telemetry['pack']['current']:.1f}A, "
                    f"SoC: {telemetry['pack']['stateOfCharge']:.1f}%, "
                    f"Phase: {telemetry['pack']['testPhase']}, "
                    f"Delta: {telemetry['pack']['cellDelta']*1000:.1f}mV"
                )
            
            # Send to IoT Hub
            if iot_client:
                try:
                    message = Message(json.dumps(telemetry))
                    message.content_type = "application/json"
                    message.content_encoding = "utf-8"
                    message.custom_properties["dataType"] = "ev_battery"
                    await iot_client.send_message(message)
                except Exception as e:
                    print(f"[IoT Hub] Send failed: {e}")
            
            await asyncio.sleep(PUBLISH_INTERVAL)
            
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        if iot_client:
            await iot_client.disconnect()
            print("[IoT Hub] Disconnected")


if __name__ == "__main__":
    asyncio.run(main())
```

## 5.4 Telemetry Schema

```json
{
  "timestamp": "2026-01-27T14:30:00.123Z",
  "deviceId": "ev-battery-lab-01",
  "dataType": "ev_battery",
  "pack": {
    "voltage": 396.42,
    "current": -150.0,
    "stateOfCharge": 78.5,
    "temperature": 32.1,
    "testPhase": "DISCHARGING",
    "cycleCount": 1247,
    "cellMin": 3.621,
    "cellMax": 3.687,
    "cellDelta": 0.066
  },
  "cells": {
    "cell_01": 3.6543,
    "cell_02": 3.6612,
    "...": "...",
    "cell_96": 3.6478
  }
}
```

## 5.5 Configuration Options

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `DEVICE_ID` | `ev-battery-lab-01` | IoT Hub device identifier |
| `NUM_CELLS` | `96` | Number of cells to simulate |
| `PUBLISH_INTERVAL` | `0.5` | Seconds between publishes (0.5 = 2Hz) |
| `IOT_HUB_CONNECTION_STRING` | (empty) | Azure IoT Hub connection string |

## 5.6 Kubernetes Deployment

**File:** `kubernetes/workloads/ev-battery-simulator/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ev-battery-simulator
  namespace: dmc-workloads
  labels:
    app: ev-battery-simulator
    workload-type: simulator
    data-profile: high-speed
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ev-battery-simulator
  template:
    metadata:
      labels:
        app: ev-battery-simulator
        workload-type: simulator
        data-profile: high-speed
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: ev-battery-simulator
          image: <your-acr-name>.azurecr.io/dmc/ev-battery-simulator:latest
          env:
            - name: DEVICE_ID
              value: "ev-battery-lab-01"
            - name: NUM_CELLS
              value: "96"
            - name: PUBLISH_INTERVAL
              value: "0.5"
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
              cpu: "250m"
```

---

# 6. Simulator: Vision Inspection

This simulator generates event-based quality inspection data with PASS/FAIL results, defect classification, and traceability metadata.

## 6.1 Business Context

IPC builds machine vision systems for defect detection. This simulator replicates:
- Discrete inspection events (not continuous time-series)
- Multi-camera configurations
- Defect classification and severity
- Full part traceability (serial numbers, batch IDs)

**Reference:** [IPC Machine Vision Defect Detection](https://www.dmcinfo.com/our-work/machine-vision-system-to-detect-defects/)

## 6.2 Dockerfile

**File:** `docker/vision-simulator/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir azure-iot-device

COPY src/simulator.py .

CMD ["python", "-u", "simulator.py"]
```

## 6.3 Python Source Code

**File:** `docker/vision-simulator/src/simulator.py`

```python
"""
Vision Inspection Simulator for IPC IPC Platform PoC
Simulates a machine vision quality inspection station

This demonstrates:
- Event-based (bursty) data pattern
- Quality metrics (PASS/FAIL with weighted rates)
- Discrete inspection results with metadata

Business Context: IPC builds machine vision systems for defect detection.
This shows the platform handles quality/inspection data, not just time-series.
"""

import asyncio
import json
import os
import random
import uuid
from datetime import datetime
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message

# Configuration
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
INSPECTION_INTERVAL = float(os.getenv("INSPECTION_INTERVAL", "5"))
DEVICE_ID = os.getenv("DEVICE_ID", "vision-station-04")
PASS_RATE = float(os.getenv("PASS_RATE", "0.95"))

# Defect types and their relative probabilities
DEFECT_TYPES = {
    "Scratch": 0.45,
    "Dent": 0.25,
    "Discoloration": 0.15,
    "Contamination": 0.10,
    "Dimensional": 0.05
}

PART_TYPES = ["Housing-A1", "Cover-B2", "Bracket-C3", "Frame-D4"]

CAMERAS = [
    {"id": "CAM-01", "position": "Top", "resolution": "5MP"},
    {"id": "CAM-02", "position": "Side-Left", "resolution": "5MP"},
    {"id": "CAM-03", "position": "Side-Right", "resolution": "5MP"},
]


class VisionInspectionStation:
    def __init__(self):
        self.inspection_count = 0
        self.pass_count = 0
        self.fail_count = 0
        self.current_batch = str(uuid.uuid4())[:8].upper()
        self.batch_count = 0
        self.batch_size = random.randint(50, 100)
        self.defect_counts = {defect: 0 for defect in DEFECT_TYPES}
        
    def perform_inspection(self) -> dict:
        """Simulate a single inspection event"""
        self.inspection_count += 1
        self.batch_count += 1
        
        # Check for batch rollover
        if self.batch_count >= self.batch_size:
            self.current_batch = str(uuid.uuid4())[:8].upper()
            self.batch_count = 0
            self.batch_size = random.randint(50, 100)
            print(f"[Batch] New batch started: {self.current_batch}")
        
        inspection_id = f"INS-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{self.inspection_count:06d}"
        passed = random.random() < PASS_RATE
        part_type = random.choice(PART_TYPES)
        part_serial = f"{part_type}-{random.randint(100000, 999999)}"
        
        result = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "deviceId": DEVICE_ID,
            "dataType": "vision_inspection",
            "inspection": {
                "id": inspection_id,
                "batchId": self.current_batch,
                "partType": part_type,
                "partSerial": part_serial,
                "result": "PASS" if passed else "FAIL",
                "processTimeMs": random.randint(120, 200),
                "confidence": round(random.uniform(0.92, 0.99), 3)
            },
            "cameras": [],
            "defects": [],
            "statistics": {
                "totalInspections": self.inspection_count,
                "totalPass": self.pass_count,
                "totalFail": self.fail_count,
                "passRate": round(self.pass_count / max(1, self.inspection_count) * 100, 2)
            }
        }
        
        # Add camera results
        for cam in CAMERAS:
            cam_result = {
                "cameraId": cam["id"],
                "position": cam["position"],
                "captureTimeMs": random.randint(15, 30),
                "analysisTimeMs": random.randint(30, 60),
                "imageQuality": round(random.uniform(0.95, 1.0), 3)
            }
            result["cameras"].append(cam_result)
        
        if passed:
            self.pass_count += 1
            result["inspection"]["defectType"] = "None"
        else:
            self.fail_count += 1
            defect_type = self._select_defect_type()
            self.defect_counts[defect_type] += 1
            result["inspection"]["defectType"] = defect_type
            
            defect_detail = {
                "type": defect_type,
                "severity": random.choice(["Minor", "Major", "Critical"]),
                "location": {
                    "x": random.randint(100, 900),
                    "y": random.randint(100, 900),
                    "width": random.randint(10, 100),
                    "height": random.randint(10, 100)
                },
                "detectedBy": random.choice([c["id"] for c in CAMERAS]),
                "confidence": round(random.uniform(0.85, 0.98), 3)
            }
            result["defects"].append(defect_detail)
        
        result["statistics"]["defectDistribution"] = dict(self.defect_counts)
        return result
    
    def _select_defect_type(self) -> str:
        r = random.random()
        cumulative = 0
        for defect, prob in DEFECT_TYPES.items():
            cumulative += prob
            if r <= cumulative:
                return defect
        return list(DEFECT_TYPES.keys())[0]


async def main():
    print("=" * 60)
    print("Vision Inspection Station Simulator")
    print("=" * 60)
    print(f"Device ID: {DEVICE_ID}")
    print(f"Inspection interval: {INSPECTION_INTERVAL}s")
    print(f"Target pass rate: {PASS_RATE * 100:.1f}%")
    print()
    
    station = VisionInspectionStation()
    
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        try:
            iot_client = IoTHubDeviceClient.create_from_connection_string(
                IOT_HUB_CONNECTION_STRING
            )
            await iot_client.connect()
            print("[IoT Hub] Connected successfully")
        except Exception as e:
            print(f"[IoT Hub] Connection failed: {e}")
            iot_client = None
    else:
        print("[IoT Hub] No connection string - local mode")
    
    print()
    print("Starting inspections...")
    print("-" * 60)
    
    try:
        while True:
            result = station.perform_inspection()
            
            status_icon = "✓" if result["inspection"]["result"] == "PASS" else "✗"
            defect_info = ""
            if result["inspection"]["result"] == "FAIL":
                defect_info = f" [{result['inspection']['defectType']}]"
            
            print(
                f"[{result['timestamp']}] "
                f"{status_icon} {result['inspection']['id']} | "
                f"{result['inspection']['partSerial']} | "
                f"{result['inspection']['result']}{defect_info} | "
                f"{result['inspection']['processTimeMs']}ms | "
                f"Rate: {result['statistics']['passRate']:.1f}%"
            )
            
            if iot_client:
                try:
                    message = Message(json.dumps(result))
                    message.content_type = "application/json"
                    message.content_encoding = "utf-8"
                    message.custom_properties["dataType"] = "vision_inspection"
                    message.custom_properties["result"] = result["inspection"]["result"]
                    await iot_client.send_message(message)
                except Exception as e:
                    print(f"[IoT Hub] Send failed: {e}")
            
            wait_time = INSPECTION_INTERVAL + random.uniform(-0.5, 0.5)
            await asyncio.sleep(max(1, wait_time))
            
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        if iot_client:
            await iot_client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
```

## 6.4 Telemetry Schema

```json
{
  "timestamp": "2026-01-27T14:30:05.456Z",
  "deviceId": "vision-station-04",
  "dataType": "vision_inspection",
  "inspection": {
    "id": "INS-20260127143005-000042",
    "batchId": "A1B2C3D4",
    "partType": "Housing-A1",
    "partSerial": "Housing-A1-847293",
    "result": "FAIL",
    "defectType": "Scratch",
    "processTimeMs": 167,
    "confidence": 0.964
  },
  "cameras": [
    {"cameraId": "CAM-01", "position": "Top", "analysisTimeMs": 45}
  ],
  "defects": [
    {
      "type": "Scratch",
      "severity": "Major",
      "location": {"x": 450, "y": 230, "width": 35, "height": 8},
      "detectedBy": "CAM-02",
      "confidence": 0.912
    }
  ],
  "statistics": {
    "totalInspections": 1847,
    "totalPass": 1756,
    "totalFail": 91,
    "passRate": 95.07
  }
}
```

## 6.5 Configuration Options

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `DEVICE_ID` | `vision-station-04` | IoT Hub device identifier |
| `INSPECTION_INTERVAL` | `5` | Seconds between inspections |
| `PASS_RATE` | `0.95` | Target pass rate (0.0 - 1.0) |
| `IOT_HUB_CONNECTION_STRING` | (empty) | Azure IoT Hub connection string |

## 6.6 Kubernetes Deployment

**File:** `kubernetes/workloads/vision-simulator/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vision-simulator
  namespace: dmc-workloads
  labels:
    app: vision-simulator
    workload-type: simulator
    data-profile: event-based
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vision-simulator
  template:
    metadata:
      labels:
        app: vision-simulator
        workload-type: simulator
        data-profile: event-based
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: vision-simulator
          image: <your-acr-name>.azurecr.io/dmc/vision-simulator:latest
          env:
            - name: DEVICE_ID
              value: "vision-station-04"
            - name: INSPECTION_INTERVAL
              value: "5"
            - name: PASS_RATE
              value: "0.95"
            - name: IOT_HUB_CONNECTION_STRING
              valueFrom:
                secretKeyRef:
                  name: iot-hub-connection
                  key: connectionString
                  optional: true
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"
```

---

# 7. Simulator: Motion/Gantry

This simulator creates an OPC-UA server exposing 3-axis servo gantry data with coordinated motion patterns and thermal management simulation.

## 7.1 Business Context

IPC programs robotic systems and servo gantries. This simulator demonstrates:
- Real-time correlated state (X, Y, Z positions move together)
- OPC-UA protocol (industry standard)
- Thermal feedback control (fan simulation)

**Reference:** [IPC Three-Axis Gantry Control](https://www.dmcinfo.com/our-work/position-control-of-a-three-axis-gantry-using-an-s7-1511-and-v90-servo-drives/)

## 7.2 Architecture

The Motion Simulator consists of two containers:
1. **Motion Simulator**: OPC-UA server exposing gantry tags
2. **Motion Gateway**: Reads OPC-UA and forwards to IoT Hub

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  AKS Edge (Containers)                                                          │
│  ┌─────────────────────────┐      ┌─────────────────────────┐                   │
│  │  Motion Simulator       │      │  Motion Gateway         │                   │
│  │  (OPC-UA Server)        │◄────►│  (OPC-UA Client)        │──────► Azure IoT  │
│  │  Port 4841              │      │                         │        Hub        │
│  └─────────────────────────┘      └─────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 7.3 Motion Simulator

### Dockerfile

**File:** `docker/motion-simulator/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir asyncua

COPY src/simulator.py .

EXPOSE 4841

CMD ["python", "-u", "simulator.py"]
```

### Python Source Code

**File:** `docker/motion-simulator/src/simulator.py`

```python
"""
Motion/Gantry Simulator for IPC IPC Platform PoC
Simulates a 3-axis servo gantry system via OPC-UA

This demonstrates:
- Real-time correlated state (X, Y, Z positions)
- Standard industrial protocol (OPC-UA)
- Temperature with feedback control (fan simulation)
"""

import asyncio
import random
import math
from datetime import datetime
from asyncua import Server, ua

OPCUA_PORT = 4841
UPDATE_INTERVAL = 0.1  # 10Hz


class GantrySimulator:
    def __init__(self):
        self.x_pos = 0.0
        self.y_pos = 0.0
        self.z_pos = 0.0
        self.x_vel = 0.0
        self.y_vel = 0.0
        self.z_vel = 0.0
        self.motor_temp = 25.0
        self.ambient_temp = 22.0
        self.fan_on = False
        self.fan_threshold_high = 45.0
        self.fan_threshold_low = 35.0
        self.pattern_phase = 0.0
        self.motion_mode = "CIRCLE"
        self.cycle_count = 0
        self.in_motion = False
        self.alarm_active = False
        self.servo_enabled = True
        
    def update(self, dt: float):
        self.pattern_phase += dt
        
        if self.motion_mode == "CIRCLE":
            radius = 100.0
            speed = 0.5
            self.x_pos = radius * math.cos(self.pattern_phase * speed)
            self.y_pos = radius * math.sin(self.pattern_phase * speed)
            self.z_pos = 50.0 + 20.0 * math.sin(self.pattern_phase * speed * 2)
            self.in_motion = True
            
        elif self.motion_mode == "PICK_PLACE":
            cycle_time = 4.0
            phase = (self.pattern_phase % cycle_time) / cycle_time
            
            if phase < 0.25:
                self.x_pos = 0.0
                self.y_pos = 0.0
                self.z_pos = 100.0 - (phase * 4 * 80)
            elif phase < 0.5:
                progress = (phase - 0.25) * 4
                self.x_pos = 150.0 * progress
                self.y_pos = 75.0 * progress
                self.z_pos = 20.0 + 30.0 * math.sin(progress * math.pi)
            elif phase < 0.75:
                self.x_pos = 150.0
                self.y_pos = 75.0
                self.z_pos = 50.0 - ((phase - 0.5) * 4 * 30)
            else:
                progress = (phase - 0.75) * 4
                self.x_pos = 150.0 * (1 - progress)
                self.y_pos = 75.0 * (1 - progress)
                self.z_pos = 20.0 + 80.0 * progress
            
            self.in_motion = True
            if phase < 0.1 and self.pattern_phase > 1:
                self.cycle_count += 1
        
        # Add noise
        self.x_pos += random.gauss(0, 0.01)
        self.y_pos += random.gauss(0, 0.01)
        self.z_pos += random.gauss(0, 0.005)
        
        self.x_vel = random.uniform(100, 200) if self.in_motion else 0
        self.y_vel = random.uniform(100, 200) if self.in_motion else 0
        self.z_vel = random.uniform(50, 100) if self.in_motion else 0
        
        # Temperature simulation
        if self.in_motion:
            self.motor_temp += 0.02 * dt
        
        cooling_rate = 0.05 if self.fan_on else 0.01
        self.motor_temp -= cooling_rate * (self.motor_temp - self.ambient_temp) * dt
        
        # Fan control with hysteresis
        if self.motor_temp > self.fan_threshold_high and not self.fan_on:
            self.fan_on = True
            print(f"[Thermal] Fan ON - Temp: {self.motor_temp:.1f}°C")
        elif self.motor_temp < self.fan_threshold_low and self.fan_on:
            self.fan_on = False
            print(f"[Thermal] Fan OFF - Temp: {self.motor_temp:.1f}°C")
        
        if self.motor_temp > 55.0 and not self.alarm_active:
            self.alarm_active = True
            print(f"[ALARM] Overtemperature! {self.motor_temp:.1f}°C")
        elif self.motor_temp <= 55.0:
            self.alarm_active = False


async def main():
    print("=" * 60)
    print("Motion/Gantry OPC-UA Simulator")
    print("=" * 60)
    print(f"OPC-UA Port: {OPCUA_PORT}")
    print(f"Update interval: {UPDATE_INTERVAL}s ({1/UPDATE_INTERVAL:.0f} Hz)")
    print()
    
    server = Server()
    await server.init()
    
    endpoint = f"opc.tcp://0.0.0.0:{OPCUA_PORT}/freeopcua/server/"
    server.set_endpoint(endpoint)
    server.set_server_name("IPC Gantry Simulator")
    
    uri = "http://dmc.com/opcua/gantry"
    idx = await server.register_namespace(uri)
    
    objects = server.nodes.objects
    gantry = await objects.add_object(idx, "GantryB")
    
    # Create variables
    x_pos = await gantry.add_variable(idx, "Axis_X_Pos", 0.0)
    y_pos = await gantry.add_variable(idx, "Axis_Y_Pos", 0.0)
    z_pos = await gantry.add_variable(idx, "Axis_Z_Pos", 0.0)
    x_vel = await gantry.add_variable(idx, "Axis_X_Vel", 0.0)
    y_vel = await gantry.add_variable(idx, "Axis_Y_Vel", 0.0)
    z_vel = await gantry.add_variable(idx, "Axis_Z_Vel", 0.0)
    motor_temp = await gantry.add_variable(idx, "Motor_Temp", 25.0)
    fan_status = await gantry.add_variable(idx, "Fan_Status", False)
    servo_enabled = await gantry.add_variable(idx, "Servo_Enabled", True)
    in_motion = await gantry.add_variable(idx, "In_Motion", False)
    alarm_active = await gantry.add_variable(idx, "Alarm_Active", False)
    cycle_count = await gantry.add_variable(idx, "Cycle_Count", 0)
    motion_mode = await gantry.add_variable(idx, "Motion_Mode", "CIRCLE")
    
    for var in [x_pos, y_pos, z_pos, x_vel, y_vel, z_vel, motor_temp, 
                fan_status, servo_enabled, in_motion, alarm_active, 
                cycle_count, motion_mode]:
        await var.set_writable()
    
    print(f"OPC-UA Server started at {endpoint}")
    print(f"Namespace: {uri}")
    print()
    print("Available tags: GantryB/Axis_X_Pos, Axis_Y_Pos, Axis_Z_Pos,")
    print("                Axis_X_Vel, Axis_Y_Vel, Axis_Z_Vel,")
    print("                Motor_Temp, Fan_Status, Servo_Enabled,")
    print("                In_Motion, Alarm_Active, Cycle_Count, Motion_Mode")
    print("-" * 60)
    
    gantry_sim = GantrySimulator()
    modes = ["CIRCLE", "PICK_PLACE"]
    mode_index = 0
    mode_timer = 0
    mode_duration = 30
    
    async with server:
        try:
            while True:
                gantry_sim.update(UPDATE_INTERVAL)
                
                mode_timer += UPDATE_INTERVAL
                if mode_timer >= mode_duration:
                    mode_timer = 0
                    mode_index = (mode_index + 1) % len(modes)
                    gantry_sim.motion_mode = modes[mode_index]
                    gantry_sim.pattern_phase = 0
                    print(f"[Mode] Switching to {gantry_sim.motion_mode}")
                
                await x_pos.write_value(round(gantry_sim.x_pos, 3))
                await y_pos.write_value(round(gantry_sim.y_pos, 3))
                await z_pos.write_value(round(gantry_sim.z_pos, 3))
                await x_vel.write_value(round(gantry_sim.x_vel, 1))
                await y_vel.write_value(round(gantry_sim.y_vel, 1))
                await z_vel.write_value(round(gantry_sim.z_vel, 1))
                await motor_temp.write_value(round(gantry_sim.motor_temp, 1))
                await fan_status.write_value(gantry_sim.fan_on)
                await servo_enabled.write_value(gantry_sim.servo_enabled)
                await in_motion.write_value(gantry_sim.in_motion)
                await alarm_active.write_value(gantry_sim.alarm_active)
                await cycle_count.write_value(gantry_sim.cycle_count)
                await motion_mode.write_value(gantry_sim.motion_mode)
                
                await asyncio.sleep(UPDATE_INTERVAL)
                
        except KeyboardInterrupt:
            print("\nShutting down...")


if __name__ == "__main__":
    asyncio.run(main())
```

### OPC-UA Tags

| Tag | Type | Description |
|-----|------|-------------|
| `GantryB/Axis_X_Pos` | Float | X position (mm) |
| `GantryB/Axis_Y_Pos` | Float | Y position (mm) |
| `GantryB/Axis_Z_Pos` | Float | Z position (mm) |
| `GantryB/Axis_X_Vel` | Float | X velocity (mm/s) |
| `GantryB/Axis_Y_Vel` | Float | Y velocity (mm/s) |
| `GantryB/Axis_Z_Vel` | Float | Z velocity (mm/s) |
| `GantryB/Motor_Temp` | Float | Motor temperature (°C) |
| `GantryB/Fan_Status` | Bool | Cooling fan state |
| `GantryB/Servo_Enabled` | Bool | Servo drive enabled |
| `GantryB/In_Motion` | Bool | Currently moving |
| `GantryB/Alarm_Active` | Bool | Overtemp alarm |
| `GantryB/Cycle_Count` | Int | Completed cycles |
| `GantryB/Motion_Mode` | String | CIRCLE/PICK_PLACE |

### Kubernetes Deployment

**File:** `kubernetes/workloads/motion-simulator/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: motion-simulator
  namespace: dmc-workloads
  labels:
    app: motion-simulator
    workload-type: simulator
    data-profile: real-time-state
spec:
  replicas: 1
  selector:
    matchLabels:
      app: motion-simulator
  template:
    metadata:
      labels:
        app: motion-simulator
        workload-type: simulator
        data-profile: real-time-state
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: motion-simulator
          image: <your-acr-name>.azurecr.io/dmc/motion-simulator:latest
          ports:
            - containerPort: 4841
              protocol: TCP
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: motion-simulator
  namespace: dmc-workloads
spec:
  selector:
    app: motion-simulator
  ports:
    - port: 4841
      targetPort: 4841
      protocol: TCP
  type: ClusterIP
```

## 7.4 Motion Gateway

The Motion Gateway reads from the Motion Simulator's OPC-UA server and forwards to Azure IoT Hub.

### Dockerfile

**File:** `docker/motion-gateway/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir asyncua azure-iot-device

COPY src/gateway.py .

CMD ["python", "-u", "gateway.py"]
```

### Python Source Code

**File:** `docker/motion-gateway/src/gateway.py`

```python
"""
Motion Gateway - OPC-UA to Azure IoT Hub
Reads gantry/motion data from Motion Simulator and publishes to IoT Hub
"""

import asyncio
import json
import os
from datetime import datetime
from asyncua import Client
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message

OPCUA_ENDPOINT = os.getenv(
    "OPCUA_ENDPOINT", 
    "opc.tcp://motion-simulator:4841/freeopcua/server/"
)
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
PUBLISH_INTERVAL = int(os.getenv("PUBLISH_INTERVAL", "1"))
DEVICE_ID = os.getenv("DEVICE_ID", "gantry-b")

TAGS = [
    "ns=2;s=GantryB/Axis_X_Pos",
    "ns=2;s=GantryB/Axis_Y_Pos",
    "ns=2;s=GantryB/Axis_Z_Pos",
    "ns=2;s=GantryB/Axis_X_Vel",
    "ns=2;s=GantryB/Axis_Y_Vel",
    "ns=2;s=GantryB/Axis_Z_Vel",
    "ns=2;s=GantryB/Motor_Temp",
    "ns=2;s=GantryB/Fan_Status",
    "ns=2;s=GantryB/Servo_Enabled",
    "ns=2;s=GantryB/In_Motion",
    "ns=2;s=GantryB/Alarm_Active",
    "ns=2;s=GantryB/Cycle_Count",
    "ns=2;s=GantryB/Motion_Mode",
]


async def main():
    print("=" * 60)
    print("Motion Gateway - OPC-UA to Azure IoT Hub")
    print("=" * 60)
    print(f"OPC-UA Endpoint: {OPCUA_ENDPOINT}")
    print(f"Device ID: {DEVICE_ID}")
    print(f"Publish Interval: {PUBLISH_INTERVAL}s")
    print()
    
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        try:
            iot_client = IoTHubDeviceClient.create_from_connection_string(
                IOT_HUB_CONNECTION_STRING
            )
            await iot_client.connect()
            print("[IoT Hub] Connected successfully")
        except Exception as e:
            print(f"[IoT Hub] Connection failed: {e}")
            iot_client = None
    else:
        print("[IoT Hub] No connection string - local mode")
    
    opcua_client = Client(OPCUA_ENDPOINT)
    
    try:
        await opcua_client.connect()
        print(f"[OPC-UA] Connected to {OPCUA_ENDPOINT}")
        
        nodes = []
        for tag in TAGS:
            try:
                node = opcua_client.get_node(tag)
                nodes.append((tag, node))
                tag_name = tag.split("/")[-1]
                print(f"  Subscribed: {tag_name}")
            except Exception as e:
                print(f"  Failed: {tag} - {e}")
        
        print()
        print("Starting telemetry loop...")
        print("-" * 60)
        
        message_count = 0
        while True:
            telemetry = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "deviceId": DEVICE_ID,
                "dataType": "motion_gantry",
                "position": {},
                "velocity": {},
                "status": {}
            }
            
            for tag_path, node in nodes:
                try:
                    value = await node.read_value()
                    tag_name = tag_path.split("/")[-1]
                    
                    if "Pos" in tag_name:
                        telemetry["position"][tag_name] = value
                    elif "Vel" in tag_name:
                        telemetry["velocity"][tag_name] = value
                    else:
                        telemetry["status"][tag_name] = value
                        
                except Exception as e:
                    print(f"Error reading {tag_path}: {e}")
            
            message_count += 1
            
            if message_count % 5 == 0:
                pos = telemetry["position"]
                status = telemetry["status"]
                print(
                    f"[{telemetry['timestamp']}] "
                    f"X:{pos.get('Axis_X_Pos', 0):.1f} "
                    f"Y:{pos.get('Axis_Y_Pos', 0):.1f} "
                    f"Z:{pos.get('Axis_Z_Pos', 0):.1f} | "
                    f"Temp:{status.get('Motor_Temp', 0):.1f}°C | "
                    f"Mode:{status.get('Motion_Mode', '?')}"
                )
            
            if iot_client:
                try:
                    message = Message(json.dumps(telemetry))
                    message.content_type = "application/json"
                    message.content_encoding = "utf-8"
                    message.custom_properties["dataType"] = "motion_gantry"
                    await iot_client.send_message(message)
                except Exception as e:
                    print(f"[IoT Hub] Send failed: {e}")
            
            await asyncio.sleep(PUBLISH_INTERVAL)
            
    except Exception as e:
        print(f"Error: {e}")
    finally:
        await opcua_client.disconnect()
        if iot_client:
            await iot_client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
```

### Kubernetes Deployment

**File:** `kubernetes/workloads/motion-gateway/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: motion-gateway
  namespace: dmc-workloads
  labels:
    app: motion-gateway
    workload-type: simulator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: motion-gateway
  template:
    metadata:
      labels:
        app: motion-gateway
        workload-type: simulator
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: motion-gateway
          image: <your-acr-name>.azurecr.io/dmc/motion-gateway:latest
          env:
            - name: OPCUA_ENDPOINT
              value: "opc.tcp://motion-simulator.dmc-workloads.svc.cluster.local:4841/freeopcua/server/"
            - name: DEVICE_ID
              value: "gantry-b"
            - name: PUBLISH_INTERVAL
              value: "1"
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
```

---

# 8. Build and Deploy

## 8.1 Build and Push All Images

On **workstation**:

```powershell
# Login to ACR
az acr login --name <your-acr-name>

# === Production Workload ===
cd C:\Projects\IPC-Platform-Engineering\docker\opcua-gateway
docker build -t "<your-acr-name>.azurecr.io/dmc/opcua-gateway:latest" .
docker push "<your-acr-name>.azurecr.io/dmc/opcua-gateway:latest"

# === Simulators ===

# OPC-UA Simulator
cd ..\opcua-simulator
docker build -t "<your-acr-name>.azurecr.io/dmc/opcua-simulator:latest" .
docker push "<your-acr-name>.azurecr.io/dmc/opcua-simulator:latest"

# EV Battery Simulator
cd ..\ev-battery-simulator
docker build -t "<your-acr-name>.azurecr.io/dmc/ev-battery-simulator:latest" .
docker push "<your-acr-name>.azurecr.io/dmc/ev-battery-simulator:latest"

# Vision Simulator
cd ..\vision-simulator
docker build -t "<your-acr-name>.azurecr.io/dmc/vision-simulator:latest" .
docker push "<your-acr-name>.azurecr.io/dmc/vision-simulator:latest"

# Motion Simulator
cd ..\motion-simulator
docker build -t "<your-acr-name>.azurecr.io/dmc/motion-simulator:latest" .
docker push "<your-acr-name>.azurecr.io/dmc/motion-simulator:latest"

# Motion Gateway
cd ..\motion-gateway
docker build -t "<your-acr-name>.azurecr.io/dmc/motion-gateway:latest" .
docker push "<your-acr-name>.azurecr.io/dmc/motion-gateway:latest"
```

## 8.2 Deploy via GitOps

```powershell
# Commit and push manifests
cd C:\Projects\IPC-Platform-Engineering
git add kubernetes/workloads/
git commit -m "Add OPC-UA gateway and industry simulators"
git push origin main

# Flux will automatically deploy within 5 minutes
# Or force immediate sync:
kubectl annotate gitrepository ipc-platform-config -n flux-system `
  reconcile.fluxcd.io/requestedAt="$(Get-Date -Format o)" --overwrite
```

---

# 9. Verification

## 9.1 Check All Pods Running

```powershell
# Check production workload
kubectl get pods -n dmc-workloads -l workload-type=production

# Check simulators
kubectl get pods -n dmc-workloads -l workload-type=simulator

# All pods should show Running status
```

## 9.2 Check Simulator Logs

```powershell
# OPC-UA Simulator
kubectl logs -n dmc-workloads -l app=opcua-simulator --tail=10

# EV Battery Simulator
kubectl logs -n dmc-workloads -l app=ev-battery-simulator --tail=10

# Vision Simulator
kubectl logs -n dmc-workloads -l app=vision-simulator --tail=10

# Motion Simulator
kubectl logs -n dmc-workloads -l app=motion-simulator --tail=10

# Motion Gateway
kubectl logs -n dmc-workloads -l app=motion-gateway --tail=10
```

## 9.3 Check Gateway Logs

```powershell
kubectl logs -n dmc-workloads -l app=opcua-gateway --tail=10

# Expected output:
# OPC-UA Gateway starting...
# Connected to OPC-UA server
# Subscribed to: ns=2;s=ProductionLine/CycleCount
# Telemetry: {"timestamp": "...", "deviceId": "...", "tags": {...}}
#   -> Sent to IoT Hub
```

## 9.4 Monitor IoT Hub Messages

```powershell
# On workstation - Monitor ALL messages arriving at IoT Hub
az iot hub monitor-events --hub-name "<your-iothub-name>" --properties all

# Filter by data type
az iot hub monitor-events --hub-name "<your-iothub-name>" --properties all | Select-String "ev_battery"
```

---

# 10. Troubleshooting

## 10.1 Pod CrashLoopBackOff

```powershell
# Check detailed events
kubectl describe pod -n dmc-workloads -l app=opcua-gateway

# Check container logs
kubectl logs -n dmc-workloads -l app=opcua-gateway --previous
```

**Common causes:**
- IoT Hub connection string invalid
- Cannot reach OPC-UA simulator service
- Python dependencies missing

## 10.2 Gateway Can't Connect to Simulator

```powershell
# Verify simulator service exists
kubectl get svc -n dmc-workloads

# Test connectivity from gateway pod
kubectl exec -it -n dmc-workloads $(kubectl get pod -n dmc-workloads -l app=opcua-gateway -o jsonpath='{.items[0].metadata.name}') -- sh
# Inside pod:
nc -zv opcua-simulator 4840
```

## 10.3 Messages Not Appearing in IoT Hub

1. Verify connection string secret exists:
   ```powershell
   kubectl get secret iot-hub-connection -n dmc-workloads
   ```

2. Check gateway logs for "WARNING: No IoT Hub connection string"

3. Verify device is registered in IoT Hub:
   ```powershell
   az iot hub device-identity show --hub-name "<your-iothub-name>" --device-id "<device-id>"
   ```

## 10.4 Image Pull Errors

```powershell
# Verify ACR pull secret exists
kubectl get secret acr-pull-secret -n dmc-workloads

# Check images exist in ACR
az acr repository list --name <your-acr-name> --output table
```

## 10.5 Motion Simulator/Gateway Issues

```powershell
# Check Motion Simulator is running and exposing OPC-UA
kubectl get svc -n dmc-workloads motion-simulator

# Test OPC-UA connectivity from Motion Gateway
kubectl exec -it -n dmc-workloads $(kubectl get pod -n dmc-workloads -l app=motion-gateway -o jsonpath='{.items[0].metadata.name}') -- sh
nc -zv motion-simulator 4841
```

---

*End of OPC-UA Gateway and Simulators Section*

**Previous:** [04-GitOps-Configuration.md](04-GitOps-Configuration.md)  
**Next:** [06-Workloads-Monitoring.md](06-Workloads-Monitoring.md)
