# OPC-UA Gateway

**Bridges OPC-UA data from factory floor to Azure IoT Hub**

## Overview

The OPC-UA Gateway connects to OPC-UA servers (like the Simulator) and forwards telemetry to Azure IoT Hub. This is a production workload that ships to customers.

## Quick Start

```bash
# Build
docker build -t opcua-gateway:local .

# Run locally (requires OPC-UA server)
docker run -e OPCUA_ENDPOINT="opc.tcp://localhost:4840/freeopcua/server/" \
           -e IOT_HUB_CONNECTION_STRING="..." \
           opcua-gateway:local

# Deploy to cluster (via GitOps)
git push origin main  # Flux handles deployment
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPCUA_ENDPOINT` | No | `opc.tcp://opcua-simulator:4840/...` | OPC-UA server URL |
| `IOT_HUB_CONNECTION_STRING` | Yes | - | Azure IoT Hub connection |
| `PUBLISH_INTERVAL` | No | `1` | Seconds between publishes |
| `DEVICE_ID` | No | `gateway-01` | Device identifier |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |

## Data Flow

```
OPC-UA Server → Gateway → Azure IoT Hub → Log Analytics
```

## Development

```bash
pip install -r requirements.txt
python src/gateway.py
```

## Documentation

- **Wiki:** [05-Workloads-OPC-UA.md](../../docs/wiki/05-Workloads-OPC-UA.md)

## Maintainer

Platform Engineering Team
