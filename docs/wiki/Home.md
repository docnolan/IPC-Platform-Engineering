# IPC Platform Engineering

**Industrial PC Platform for Edge Computing, Compliance, and Zero-Touch Operations**

---

## The Three Pillars

| Pillar | Description | Documentation |
|--------|-------------|---------------|
| Automated Provisioning | Packer golden images with CIS hardening, Windows 10 IoT Enterprise LTSC 2021 | [Golden Image Pipeline](02-Golden-Image-Pipeline.md) |
| Compliance as a Service | Real-time audit logging, NIST 800-171 mapping, 90-day retention | [Compliance](09-Compliance-as-a-Service.md) |
| Zero-Touch Updates | GitOps deployment via Flux, automatic image updates, no truck rolls | [GitOps Configuration](04-GitOps-Configuration.md) |

---

## Quick Start

| Task | Guide |
|------|-------|
| Understand the architecture | [Platform Overview](00-Overview.md) |
| Set up Azure foundation | [Azure Foundation](01-Azure-Foundation.md) |
| Deploy edge cluster | [Edge Deployment](03-Edge-Deployment.md) |
| View workload catalog | [OPC-UA](05-Workloads-OPC-UA.md) • [Monitoring](06-Workloads-Monitoring.md) • [Analytics](07-Workloads-Analytics.md) |
| Troubleshoot issues | [Troubleshooting](A1-Troubleshooting.md) |
| Command reference | [Quick Reference](A2-Quick-Reference.md) |

---

## Documentation Index

### Core Platform

| # | Document | Description |
|---|----------|-------------|
| 00 | [Overview](00-Overview.md) | Architecture, design principles, three pillars |
| 01 | [Azure Foundation](01-Azure-Foundation.md) | Resource groups, Workload Identity Federation, networking |
| 02 | [Golden Image Pipeline](02-Golden-Image-Pipeline.md) | Packer templates, CIS hardening, Windows 10 IoT Enterprise LTSC 2021 |
| 03 | [Edge Deployment](03-Edge-Deployment.md) | AKS Edge Essentials, Azure Arc connection |
| 04 | [GitOps Configuration](04-GitOps-Configuration.md) | Flux setup, image automation, zero-touch updates |

### Workloads

| # | Document | Workloads Covered |
|---|----------|-------------------|
| 05 | [OPC-UA Workloads](05-Workloads-OPC-UA.md) | opcua-simulator, opcua-gateway |
| 06 | [Monitoring Workloads](06-Workloads-Monitoring.md) | health-monitor, log-forwarder |
| 07 | [Analytics Workloads](07-Workloads-Analytics.md) | anomaly-detection, test-data-collector, ev-battery-simulator, vision-simulator, motion-simulator, motion-gateway |

### Operations

| # | Document | Description |
|---|----------|-------------|
| 08 | [CI/CD Pipelines](08-CI-CD-Pipelines.md) | Build, scan, sign pipelines with Trivy |
| 09 | [Compliance as a Service](09-Compliance-as-a-Service.md) | NIST mapping, KQL queries, audit evidence |
### Reference

| # | Document | Description |
|---|----------|-------------|
| A1 | [Troubleshooting](A1-Troubleshooting.md) | Common issues and solutions |
| A2 | [Quick Reference](A2-Quick-Reference.md) | Commands, scripts, cheat sheet |

---



## Repository Structure

```
IPC-Platform-Engineering/
├── docker/              # Workload containers (10 workloads)
├── kubernetes/          # K8s manifests, Flux config
├── packer/              # Golden image templates
├── pipelines/           # Azure DevOps CI/CD
├── scripts/             # Utility PowerShell scripts
├── compliance/          # Evidence collection, KQL queries
├── observability/       # Dashboards, alerts
└── docs/
    ├── wiki/            # This documentation
    ├── architecture/    # ADRs
    └── security/        # Risk register
```

---

*Last Updated: 2026-01-30*
