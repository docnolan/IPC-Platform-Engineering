# Anomaly Detection

**Edge-based statistical anomaly detection for industrial sensor data**

## Overview

Runs lightweight statistical anomaly detection on OPC-UA sensor data at the edge. Only sends alerts to the cloud—not raw data—reducing bandwidth and enabling sub-second detection latency.

## Quick Start

```bash
# Build
docker build -t anomaly-detection:local .

# Run locally (requires OPC-UA server)
docker run -e OPCUA_ENDPOINT="opc.tcp://localhost:4840/freeopcua/server/" \
           anomaly-detection:local

# Deploy to cluster (via GitOps)
git push origin main
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPCUA_ENDPOINT` | No | `opc.tcp://opcua-simulator:4840/...` | OPC-UA server URL |
| `IOT_HUB_CONNECTION_STRING` | No | - | For sending alerts |
| `DETECTION_INTERVAL` | No | `5` | Seconds between checks |
| `WINDOW_SIZE` | No | `20` | Samples in sliding window |
| `ANOMALY_THRESHOLD` | No | `2.5` | Standard deviations |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |

## Algorithm

Uses z-score based detection:
1. Maintains sliding window of last N samples
2. Calculates mean and standard deviation
3. Flags values > threshold σ from mean

## Development

```bash
pip install -r requirements.txt
python src/detector.py
```

## Documentation

- **Wiki:** [07-Workloads-Analytics.md](../../docs/wiki/07-Workloads-Analytics.md)

## Maintainer

Platform Engineering Team
