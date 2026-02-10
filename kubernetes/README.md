# Kubernetes Manifests (GitOps)

This directory contains the Kubernetes manifests managed by Flux CD. It is the **Source of Truth** for the edge cluster state.

## Documentation

> 📘 **See [Wiki: 04-GitOps-Configuration](../docs/wiki/04-GitOps-Configuration.md) for Flux setup and troubleshooting.**

## structure
- `workloads/`: Applications deployed to the `dmc-workloads` namespace.
- `flux-system/`: Flux configuration and image automation.
- `addons/`: Cluster add-ons (Metrics Server, Akri, etc.).
