# ADR-0001: Edge Kubernetes with AKS Edge Essentials

## Status
Accepted

## Date
2026-01-20

## Context
DMC's IPC Platform requires a Kubernetes distribution suitable for edge deployment on Windows 11 IoT Enterprise industrial PCs. Requirements include:

- Running on Windows 11 IoT Enterprise LTSC with limited resources (16GB RAM, 4 cores typical)
- Integration with Azure Arc for centralized management
- GitOps support via Flux
- Container workload isolation without full hypervisor overhead
- Maintenance by Microsoft with enterprise support

## Decision
We will use **AKS Edge Essentials** as the Kubernetes distribution for edge IPCs.

AKS Edge Essentials:
- Provides a lightweight Linux VM (~4GB) using WSL2 or Hyper-V isolation
- Includes Microsoft-supported K3s distribution
- Has native Azure Arc integration via `az aksedge` CLI
- Supports GitOps with Flux v2 extension
- Receives Windows Update patches automatically

## Consequences

### Positive
- **Azure-native integration**: Arc connection works out of the box
- **Microsoft support**: Production SLA available, not community-only
- **Flux extension**: Built-in GitOps via Azure Arc, no manual Flux installation
- **Lightweight**: Runs on factory IPCs with 16GB RAM alongside Windows workloads
- **CIS Hardening**: Compatible with CIS-hardened base images

### Negative
- **Windows-only**: Host must be Windows 10/11; cannot run on Linux-only edge devices
- **Single-node limitation**: PoC uses single-node; HA requires multiple machines
- **Memory overhead**: Linux VM consumes ~4GB even when idle
- **K3s differences**: Some full K8s features may differ in K3s

### Neutral
- Hyper-V licensing may be required for production (included in Windows 11 IoT Enterprise)

## Alternatives Considered

### K3s standalone (on Linux)
- Pros: Lighter weight, runs on Linux
- Why not: Customer IPCs are Windows; would require dual-boot or separate device

### MicroK8s
- Pros: Ubuntu-based, full K8s API
- Why not: Less native Azure integration; Canonical support vs. Microsoft support

### Azure IoT Edge (without Kubernetes)
- Pros: Simpler for basic IoT scenarios
- Why not: Doesn't support arbitrary container workloads; less flexibility

### Full AKS (Azure-hosted)
- Pros: Maximum features
- Why not: Requires cloud connectivity; doesn't run on-premise workloads

## References
- [AKS Edge Essentials documentation](https://learn.microsoft.com/en-us/azure/aks/hybrid/aks-edge-overview)
- [Azure Arc-enabled Kubernetes](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/)
