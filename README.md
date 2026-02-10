# IPC Platform Engineering

This repository contains the infrastructure-as-code for the IPC Platform, transforming standard IPCs into managed, monitored, and compliant edge devices.

## Repository Structure

- `packer/` - Golden image definitions (Windows 10 IoT Enterprise LTSC)
- `pipelines/` - Azure DevOps CI/CD pipelines
- `kubernetes/` - Kubernetes manifests for edge workloads (Flux GitOps)
- `terraform/` - Azure Infrastructure-as-Code
- `docker/` - Dockerfiles for containerized services
- `compliance/` - CIS benchmark and NIST 800-171 scripts
- `docs/` - Architecture and operational documentation
- `scripts/` - Utility scripts

## Quick Start & Documentation

The primary documentation resides in the **Wiki** (`docs/wiki/`).

| Capability | Documentation Link |
| :--- | :--- |
| **System Overview** | [00-Overview](docs/wiki/00-Overview.md) |
| **Edge Deployment** | [03-Edge-Deployment](docs/wiki/03-Edge-Deployment.md) |
| **GitOps/Flux** | [04-GitOps-Configuration](docs/wiki/04-GitOps-Configuration.md) |
| **CI/CD Pipelines** | [08-CI-CD-Pipelines](docs/wiki/08-CI-CD-Pipelines.md) |
| **Compliance/NIST** | [09-Compliance-as-a-Service](docs/wiki/09-Compliance-as-a-Service.md) |

## Compliance

This platform implements **CIS Benchmark Level 1** hardening and addresses **NIST 800-171** technical controls. See [09-Compliance-as-a-Service](docs/wiki/09-Compliance-as-a-Service.md) for details.
