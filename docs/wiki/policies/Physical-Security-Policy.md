# Physical Security Policy
**Control ID:** NIST 3.10.1
**Effective Date:** 2026-02-04
**Scope:** All facilities hosting IPC Platform equipment.

## Policy Statement
The Company requires that all physical access to organizational information systems, equipment, and the respective operating environments is limited to authorized individuals.

## Requirements

### 1. Facility Access
- Access to the manufacturing floor and server rooms is restricted to authorized personnel via badge access.
- Visitors must be escorted at all times and logged in the Visitor Access Log.
- Physical keys to server cabinets must be stored in a secured key box accessible only to IT/OT administrators.

### 2. Device Security
- IPC devices must be mounted in locked enclosures or cabinets.
- Unused physical ports (USB, Ethernet) on IPC devices must be physically blocked or logically disabled (see `03-harden-cis-benchmark.ps1`).
- Devices must not be left logged in and unattended.

### 3. Monitoring
- Physical access points to critical infrastructure areas are monitored by CCTV with 30-day retention.
- Access logs are reviewed quarterly by the Security Officer.

## Enforcement
Violations of this policy may result in disciplinary action up to and including termination of employment.
