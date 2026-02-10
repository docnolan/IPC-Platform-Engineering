# EV Battery Simulator

**Simulates a 96-cell EV battery pack for end-of-line test systems**

## Overview

Simulates high-speed battery pack telemetry including cell voltages, pack current, state of charge, and temperature. Demonstrates DMC's EV battery test system capabilities—their high-volume revenue driver.

## Quick Start

```bash
# Build
docker build -t ev-battery-simulator:local .

# Run locally
docker run -e IOT_HUB_CONNECTION_STRING="..." ev-battery-simulator:local

# Deploy to cluster (via GitOps)
git push origin main
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `IOT_HUB_CONNECTION_STRING` | No | - | Azure IoT Hub connection |
| `PUBLISH_INTERVAL` | No | `0.5` | Seconds (2Hz default) |
| `DEVICE_ID` | No | `ev-battery-lab-01` | Device identifier |
| `NUM_CELLS` | No | `96` | Number of cells |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (port 8080) |

## Test Phases

| Phase | Description |
|-------|-------------|
| IDLE | System waiting |
| DISCHARGING | 150A discharge to 20% SoC |
| REST | Cool-down period |
| CHARGING | 75A charge to 95% SoC |

## Telemetry

- Pack voltage, current, temperature
- 96 individual cell voltages
- Cell min/max/delta statistics

## Development

```bash
pip install -r requirements.txt
python src/simulator.py
```

## Documentation

- **Wiki:** [07-Workloads-Analytics.md](../../docs/wiki/07-Workloads-Analytics.md)

## Maintainer

Platform Engineering Team
