# Identity and Access Management Policy
**Control ID:** NIST 3.5.3, 3.7.1
**Effective Date:** 2026-02-04
**Scope:** All users and systems accessing the IPC Platform.

## Policy Statement
IPC enforces strong identity verification and precise access control for all systems. Access is granted on a "need-to-know" basis and requires Multifactor Authentication (MFA) for non-local access.

## Requirements

### 1. Multifactor Authentication (MFA)
- **Control 3.5.3**: Use multifactor authentication for local and network access to privileged accounts and for network access to non-privileged accounts.
- **Implementation**:
    - All Azure AD (Entra ID) access requires MFA enforced via Conditional Access Policies.
    - VPN or Remote Desktop access to the OT network requires MFA.
    - *Exception*: Local console access for emergency "break-glass" accounts (physically secured).

### 2. Maintenance Personnel
- **Control 3.7.1**: Perform maintenance on organizational systems, and provide controls on the tools, techniques, mechanisms, and personnel used to conduct system maintenance.
- **Implementation**:
    - Only authorized maintenance personnel are permitted to service IPC equipment.
    - Vendor maintenance (remote) must be supervised and utilize a secure, time-boxed connection (e.g., Azure Just-In-Time Access).
    - All maintenance activities must be logged in the Change Management System.

### 3. Role-Based Access Control (RBAC)
- Access rights are assigned based on job role.
- Periodic access reviews are conducted (minimum annually) to revoke unnecessary privileges.

## Enforcement
Violations of this policy may result in disciplinary action up to and including termination of employment.
