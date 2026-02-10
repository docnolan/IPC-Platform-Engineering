# OPC-UA Simulator

**Simulates a PLC with OPC-UA server for industrial data simulation**

## Overview

The OPC-UA Simulator emulates a generic PLC exposing sensor data via OPC-UA protocol. It provides temperature, pressure, and vibration readings for testing the Gateway and Anomaly Detection workloads.

## Quick Start

```bash
# Build
docker build -t opcua-simulator:local .

# Run locally
docker run -p 4840:4840 opcua-simulator:local

# Deploy to cluster (via GitOps)
git push origin main  # Flux handles deployment
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `UPDATE_INTERVAL` | No | `1` | Seconds between value updates |

## Endpoints

| Endpoint | Protocol | Description |
|----------|----------|-------------|
| Port 4840 | OPC-UA | OPC-UA server endpoint |
| `/health` | HTTP | Kubernetes health check |

## OPC-UA Tags

| Tag | Description | Unit |
|-----|-------------|------|
| `ns=2;s=ProductionLine/Temperature` | Ambient temperature | °F |
| `ns=2;s=ProductionLine/Pressure` | Line pressure | PSI |
| `ns=2;s=ProductionLine/Vibration` | Machine vibration | g |

## Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run locally
python src/simulator.py
```

## Documentation

- **Wiki:** [05-Workloads-OPC-UA.md](../../docs/wiki/05-Workloads-OPC-UA.md)
- **ADR:** [ADR-0002-gitops-flux.md](../../docs/architecture/decisions/ADR-0002-gitops-flux.md)

## Maintainer

Platform Engineering Team
