# Motion Gateway

**Bridges motion gantry OPC-UA data to Azure IoT Hub**

## Overview

Connects to the Motion Simulator's OPC-UA server and forwards telemetry (position, velocity, temperature) to Azure IoT Hub. Demonstrates gateway pattern for motion control systems.

## Quick Start

```bash
# Build
docker build -t motion-gateway:local .

# Run locally (requires motion-simulator)
docker run -e OPCUA_ENDPOINT="opc.tcp://localhost:4841/freeopcua/server/" \
           -e IOT_HUB_CONNECTION_STRING="..." \
           motion-gateway:local

# Deploy to cluster (via GitOps)
git push origin main
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPCUA_ENDPOINT` | No | `opc.tcp://motion-simulator:4841/...` | OPC-UA URL |
| `IOT_HUB_CONNECTION_STRING` | No | - | Azure IoT Hub connection |
| `PUBLISH_INTERVAL` | No | `1` | Seconds between publishes |
| `DEVICE_ID` | No | `gantry-b` | Device identifier |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (port 8080) |

## Telemetry Schema

```json
{
  "dataType": "motion_gantry",
  "position": { "Axis_X_Pos": 85.2, ... },
  "velocity": { "Axis_X_Vel": 150.2, ... },
  "status": { "Motor_Temp": 38.5, "Fan_Status": true, ... }
}
```

## Dependencies

Requires `motion-simulator` to be running.

## Development

```bash
pip install -r requirements.txt
python src/gateway.py
```

## Documentation

- **Wiki:** [07-Workloads-Analytics.md](../../docs/wiki/07-Workloads-Analytics.md)

## Maintainer

Platform Engineering Team
