# Motion Simulator

**Simulates a 3-axis servo gantry system via OPC-UA**

## Overview

Simulates a CNC-style 3-axis gantry with position, velocity, temperature, and fan control. Exposes data via OPC-UA protocol for consumption by Motion Gateway.

## Quick Start

```bash
# Build
docker build -t motion-simulator:local .

# Run locally
docker run -p 4841:4841 -p 8080:8080 motion-simulator:local

# Deploy to cluster (via GitOps)
git push origin main
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPCUA_PORT` | No | `4841` | OPC-UA server port |
| `HEALTH_PORT` | No | `8080` | Health endpoint port |
| `UPDATE_INTERVAL` | No | `0.1` | Update rate (10Hz) |

## Endpoints

| Endpoint | Protocol | Description |
|----------|----------|-------------|
| Port 4841 | OPC-UA | GantryB namespace |
| Port 8080 `/health` | HTTP | Health check |

## OPC-UA Tags

| Tag | Description |
|-----|-------------|
| `Axis_X_Pos`, `Axis_Y_Pos`, `Axis_Z_Pos` | Position (mm) |
| `Axis_X_Vel`, `Axis_Y_Vel`, `Axis_Z_Vel` | Velocity (mm/s) |
| `Motor_Temp` | Temperature (°C) |
| `Fan_Status` | Cooling fan state |
| `Motion_Mode` | CIRCLE or PICK_PLACE |

## Motion Patterns

| Pattern | Description |
|---------|-------------|
| CIRCLE | Continuous circular motion |
| PICK_PLACE | 4-phase pick and place cycle |

## Development

```bash
pip install -r requirements.txt
python src/simulator.py
```

## Documentation

- **Wiki:** [07-Workloads-Analytics.md](../../docs/wiki/07-Workloads-Analytics.md)

## Maintainer

Platform Engineering Team
