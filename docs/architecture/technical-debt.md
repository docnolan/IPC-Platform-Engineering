# Technical Debt Register

This document tracks known technical debt, "hacks", and temporary workarounds in the platform.
It serves as a backlog for refactoring and stability improvements.

## Active Debt

| ID | Component | Description | Risk | Remediation Plan |
|----|-----------|-------------|------|------------------|
| TD-001 | VM Network | `<edge-vm-name>` API port requires specific firewall rules not automated in Packer | Compliance/Access | Automate firewall rule in `02-configure-windows-features.ps1` |
| TD-002 | GitOps | Flux sync interval is default (1m); too aggressive for edge | Performance | Tune `flux-system` Kustomization to 10m+ |
| TD-003 | Documentation | Multiple assessment reports in `.gemini` folder, not Wiki | Knowledge Loss | Migrate key findings to `docs/wiki/reports/` |
| TD-004 | Secrets | Local creds used for VM access (PowerShell Direct) | Security | Move to LAPS when AD integration is complete |

## Resolved Debt

| ID | Description | Resolution | Date |
|----|-------------|------------|------|
| - | - | - | - |
