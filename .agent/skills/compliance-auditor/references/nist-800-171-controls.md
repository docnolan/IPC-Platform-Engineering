# NIST 800-171 Control Reference

Quick reference for NIST 800-171 controls relevant to the IPC Platform. This document maps controls to platform implementations and evidence sources.

## Control Families Overview

| Family | Name | Platform Relevance |
|--------|------|-------------------|
| 3.1 | Access Control | RBAC, Kubernetes policies, Azure permissions |
| 3.3 | Audit and Accountability | Log forwarder, health monitor, Log Analytics |
| 3.4 | Configuration Management | Golden image, Packer, GitOps baselines |
| 3.5 | Identification and Authentication | Service principals, secrets management |
| 3.8 | Media Protection | BitLocker (Phase 1), backup policies |
| 3.11 | Risk Assessment | Vulnerability scanning (Phase 1) |
| 3.13 | System and Communications Protection | TLS, network segmentation, encryption |
| 3.14 | System and Information Integrity | Patching, integrity monitoring |

---

## Controls Implemented by PoC

### 3.1 Access Control

| Control | Requirement | Implementation | Evidence |
|---------|-------------|----------------|----------|
| 3.1.1 | Limit system access to authorized users | CIS hardening disables guest accounts | `net user` output |
| 3.1.2 | Limit system access to authorized functions | Kubernetes RBAC, namespace isolation | `kubectl get rolebindings` |
| 3.1.7 | Prevent non-privileged users from executing privileged functions | UAC enabled, admin separation | CIS audit results |

**KQL Evidence Query (3.1.1):**
```kql
IPCSecurityAudit_CL
| where EventID_d == 4624  // Successful logon
| summarize count() by Account_s, LogonType_d
| where LogonType_d in (2, 10)  // Interactive, RemoteInteractive
```

### 3.3 Audit and Accountability

| Control | Requirement | Implementation | Evidence |
|---------|-------------|----------------|----------|
| 3.3.1 | Create and retain audit logs | Log forwarder → Log Analytics | `IPCSecurityAudit_CL` table |
| 3.3.2 | Ensure actions traceable to users | Windows Security log capture | Event correlation |
| 3.3.8 | Protect audit information | Immutable Azure storage | Azure RBAC on workspace |

**KQL Evidence Query (3.3.1):**
```kql
IPCSecurityAudit_CL
| where TimeGenerated > ago(90d)
| summarize EventCount = count() by bin(TimeGenerated, 1d)
| order by TimeGenerated desc
```

### 3.4 Configuration Management

| Control | Requirement | Implementation | Evidence |
|---------|-------------|----------------|----------|
| 3.4.1 | Establish baseline configurations | Golden image via Packer | Packer template in Git |
| 3.4.2 | Establish security configuration settings | CIS Benchmark hardening | Hardening script output |
| 3.4.5 | Define and document changes | GitOps workflow | Git commit history |

**Evidence Location:**
- Baseline: `packer/windows-iot-enterprise/windows-iot.pkr.hcl`
- Hardening: `packer/windows-iot-enterprise/scripts/`
- Changes: `git log --oneline`

### 3.5 Identification and Authentication

| Control | Requirement | Implementation | Evidence |
|---------|-------------|----------------|----------|
| 3.5.1 | Identify system users | Windows local accounts | `net user` output |
| 3.5.2 | Authenticate users | Password policy via CIS | `net accounts` output |
| 3.5.10 | Store credentials securely | Azure Key Vault references | No secrets in Git |

**Password Policy Evidence:**
```powershell
net accounts
# Verify: Minimum password length >= 14
# Verify: Lockout threshold <= 5
```

### 3.13 System and Communications Protection

| Control | Requirement | Implementation | Evidence |
|---------|-------------|----------------|----------|
| 3.13.1 | Monitor communications at boundaries | Outbound-only architecture | Network diagram |
| 3.13.8 | Implement cryptographic mechanisms | TLS 1.2+ for all Azure traffic | Certificate verification |
| 3.13.11 | Employ FIPS-validated cryptography | FIPS mode (Phase 1) | Registry setting |

**TLS Evidence:**
```powershell
# Verify outbound connections use TLS
Test-NetConnection -ComputerName "management.azure.com" -Port 443
```

---

## Controls NOT YET Implemented (Production Roadmap)

### Phase 1 Gaps

| Control | Requirement | Gap | Remediation |
|---------|-------------|-----|-------------|
| 3.1.2 | Limit transaction types | No AppLocker/WDAC | Implement application whitelisting |
| 3.5.3 | Use MFA | No MFA configured | Implement Windows Hello/Entra ID |
| 3.8.1 | Protect media | No BitLocker | Enable full disk encryption |
| 3.12.1 | Assess security controls | No vulnerability scanning | Add Defender/Trivy to pipeline |
| 3.13.11 | FIPS cryptography | Not enforced | Enable FIPS mode registry setting |

### Phase 3 Gaps

| Control | Requirement | Gap | Remediation |
|---------|-------------|-----|-------------|
| 3.5.3 | MFA for all users | Local accounts only | Entra ID integration |
| 3.7.1 | Maintenance personnel | No formal process | Identity management system |
| 3.10.1 | Physical access | Out of scope | Customer responsibility |

---

## Compliance Evidence Templates

### Monthly Audit Evidence Package

```
AUDIT EVIDENCE PACKAGE
======================
Period: [Month Year]
Generated: [Timestamp]
System: IPC Platform - [Customer/Site]

1. ACCESS CONTROL (3.1)
   - User account listing
   - RBAC configuration
   - Failed logon attempts

2. AUDIT LOGS (3.3)
   - Log collection verification
   - Sample security events
   - 90-day retention proof

3. CONFIGURATION (3.4)
   - Current baseline version
   - Change log for period
   - Drift detection results

4. AUTHENTICATION (3.5)
   - Password policy settings
   - Account lockout events
   - Service principal inventory

5. COMMUNICATIONS (3.13)
   - TLS certificate status
   - Network connection audit
   - Encryption verification
```

### Control Attestation Statement

```
CONTROL ATTESTATION
===================
Control ID: [3.X.X]
Control Name: [Name]
Assessment Date: [Date]

Implementation Status: [Implemented / Partially Implemented / Not Implemented]

Description of Implementation:
[How the control is implemented in the platform]

Evidence Reviewed:
- [Evidence item 1]
- [Evidence item 2]

Gaps Identified:
- [Gap 1, if any]

Assessor: [Name]
Approval: [Lead Engineer]
```

---

## KQL Query Library

### Failed Logon Attempts (3.1, 3.5)
```kql
IPCSecurityAudit_CL
| where EventID_d == 4625
| where TimeGenerated > ago(24h)
| project TimeGenerated, Computer_s, Account_s, FailureReason_s
| order by TimeGenerated desc
```

### Audit Log Volume (3.3)
```kql
IPCSecurityAudit_CL
| where TimeGenerated > ago(7d)
| summarize DailyCount = count() by bin(TimeGenerated, 1d), Computer_s
| render timechart
```

### Configuration Changes (3.4)
```kql
IPCSecurityAudit_CL
| where EventID_d in (4719, 4739, 4906)  // Policy changes
| where TimeGenerated > ago(30d)
| project TimeGenerated, EventID_d, Computer_s, Message_s
```

### Privileged Account Usage (3.1.7)
```kql
IPCSecurityAudit_CL
| where EventID_d == 4672  // Special privileges assigned
| where TimeGenerated > ago(24h)
| summarize count() by Account_s
| order by count_ desc
```

---

## Quick Reference: CMMC Level 2 Mapping

CMMC Level 2 requires all 110 NIST 800-171 controls. The IPC Platform addresses:

| Status | Count | Notes |
|--------|-------|-------|
| Fully Implemented | 15 | Core logging, access control, configuration |
| Partially Implemented | 8 | Need hardening completion |
| Not Implemented | 12 | Phase 1-3 roadmap items |
| Not Applicable | 5 | Physical security (customer) |
| Customer Responsibility | 70 | Organizational controls |

**Platform-addressable controls: 35 of 40 technical controls (87.5%)**
