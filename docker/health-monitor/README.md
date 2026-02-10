# Health Monitor

**Collects system health metrics and forwards to Azure Log Analytics**

## Overview

The Health Monitor collects CPU, memory, disk, and process information from the edge node and sends it to Azure Log Analytics. This is a production workload essential for remote monitoring.

## Quick Start

```bash
# Build
docker build -t health-monitor:local .

# Run locally
docker run -e LOG_ANALYTICS_WORKSPACE_ID="..." \
           -e LOG_ANALYTICS_KEY="..." \
           health-monitor:local

# Deploy to cluster (via GitOps)
git push origin main
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LOG_ANALYTICS_WORKSPACE_ID` | Yes | - | Workspace ID |
| `LOG_ANALYTICS_KEY` | Yes | - | Workspace primary key |
| `COLLECTION_INTERVAL` | No | `60` | Seconds between collections |
| `DEVICE_ID` | No | hostname | Device identifier |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |

## Metrics Collected

| Metric | Description |
|--------|-------------|
| `system_cpu_percent` | CPU utilization |
| `system_memory_percent` | Memory utilization |
| `system_disk_percent` | Disk utilization |
| `system_uptime_seconds` | System uptime |

## Development

```bash
pip install -r requirements.txt
python src/monitor.py
```

## Documentation

- **Wiki:** [06-Workloads-Monitoring.md](../../docs/wiki/06-Workloads-Monitoring.md)

## Maintainer

Platform Engineering Team
