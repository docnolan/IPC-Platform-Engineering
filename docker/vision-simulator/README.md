# Vision Simulator

**Simulates a machine vision quality inspection station**

## Overview

Simulates a 3-camera quality inspection system with PASS/FAIL results, defect classification, and batch tracking. Demonstrates manufacturing quality inspection use cases.

## Quick Start

```bash
# Build
docker build -t vision-simulator:local .

# Run locally
docker run -e IOT_HUB_CONNECTION_STRING="..." vision-simulator:local

# Deploy to cluster (via GitOps)
git push origin main
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `IOT_HUB_CONNECTION_STRING` | No | - | Azure IoT Hub connection |
| `INSPECTION_INTERVAL` | No | `5` | Seconds between inspections |
| `DEVICE_ID` | No | `vision-station-04` | Station identifier |
| `PASS_RATE` | No | `0.95` | Target pass rate (95%) |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (port 8080) |

## Defect Types

| Defect | Probability |
|--------|-------------|
| Scratch | 45% |
| Dent | 25% |
| Discoloration | 15% |
| Contamination | 10% |
| Dimensional | 5% |

## Part Types

- Housing-A1, Cover-B2, Bracket-C3, Frame-D4

## Development

```bash
pip install -r requirements.txt
python src/simulator.py
```

## Documentation

- **Wiki:** [07-Workloads-Analytics.md](../../docs/wiki/07-Workloads-Analytics.md)

## Maintainer

Platform Engineering Team
