# Test Data Collector

**Watches for test result files and uploads to Azure Blob Storage**

## Overview

Monitors a local directory for test result files (CSV, JSON) from LabVIEW or .NET test applications. Uploads to Azure Blob Storage with metadata for full traceability.

## Quick Start

```bash
# Build
docker build -t test-data-collector:local .

# Run locally
docker run -v /path/to/results:/data/test-results \
           -e BLOB_CONNECTION_STRING="..." \
           test-data-collector:local

# Deploy to cluster (via GitOps)
git push origin main
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WATCH_DIR` | No | `/data/test-results` | Directory to watch |
| `BLOB_CONNECTION_STRING` | Yes | - | Azure Storage connection |
| `BLOB_CONTAINER` | No | `test-results` | Target container |
| `IOT_HUB_CONNECTION_STRING` | No | - | For summary messages |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |

## Blob Path Format

```
{deviceId}/{yyyy/MM/dd}/{filename}.json
```

## Supported Formats

- CSV with header row
- JSON files

## Development

```bash
pip install -r requirements.txt
python src/collector.py
```

## Documentation

- **Wiki:** [07-Workloads-Analytics.md](../../docs/wiki/07-Workloads-Analytics.md)

## Maintainer

Platform Engineering Team
