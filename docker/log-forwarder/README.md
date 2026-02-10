# Log Forwarder

**Forwards Windows Security Event logs to Azure Log Analytics**

## Overview

The Log Forwarder reads Windows Security Event logs and forwards them to Azure Log Analytics for centralized audit trail. Supports NIST 800-171 audit logging requirements.

## Quick Start

```bash
# Build
docker build -t log-forwarder:local .

# Run locally
docker run -e LOG_ANALYTICS_WORKSPACE_ID="..." \
           -e LOG_ANALYTICS_KEY="..." \
           log-forwarder:local

# Deploy to cluster (via GitOps)
git push origin main
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LOG_ANALYTICS_WORKSPACE_ID` | Yes | - | Workspace ID |
| `LOG_ANALYTICS_KEY` | Yes | - | Workspace primary key |
| `FORWARD_INTERVAL` | No | `30` | Seconds between forwards |
| `DEVICE_ID` | No | hostname | Source device ID |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |

## Events Forwarded

| Event ID | Description | Compliance Control |
|----------|-------------|-------------------|
| 4624 | Successful logon | NIST 3.1.7 |
| 4625 | Failed logon | NIST 3.1.8 |
| 4648 | Explicit credential logon | NIST 3.1.12 |

## Development

```bash
pip install -r requirements.txt
python src/forwarder.py
```

## Documentation

- **Wiki:** [06-Workloads-Monitoring.md](../../docs/wiki/06-Workloads-Monitoring.md)
- **Compliance:** [09-Compliance-as-a-Service.md](../../docs/wiki/09-Compliance-as-a-Service.md)

## Maintainer

Platform Engineering Team
