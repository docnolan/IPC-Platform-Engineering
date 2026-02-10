# ADR-0005: CIS Hardened Base Images

## Status
Accepted

## Date
2026-01-20

## Context
The IPC Platform targets defense and regulated manufacturing customers requiring:

- Documented security baseline
- Compliance with industry standards (NIST 800-171, CMMC Level 2)
- Auditable hardening configuration
- Reproducible builds

Factory IPCs run Windows 11 IoT Enterprise LTSC. The base VM image needs systematic hardening beyond out-of-box configuration.

## Decision
We will create **Packer-built golden images** with CIS Benchmark Level 1 hardening applied automatically.

Implementation:
- Packer templates in `packer/dmc-golden.pkr.hcl`
- CIS Windows 11 Enterprise Level 1 benchmark (STIG where applicable)
- PowerShell DSC for configuration management
- Output: VHD/VHDX ready for Hyper-V deployment

Hardening includes:
- Bitlocker encryption enabled
- Windows Firewall configured
- Audit logging enabled (security events forwarded to Log Analytics)
- Unnecessary services disabled
- Password policies enforced

## Consequences

### Positive
- **Audit-ready**: CIS provides documentation and audit evidence
- **Reproducible**: Packer templates are version-controlled
- **Consistent**: Every IPC gets identical configuration
- **Compliance**: Directly maps to NIST 800-171 and CMMC controls
- **Self-documenting**: Hardening script shows exactly what changed

### Negative
- **Maintenance burden**: Must update when CIS benchmarks change
- **Customization conflicts**: Some CIS settings may conflict with DMC applications
- **Build time**: Full image build takes ~30 minutes

### Neutral
- Requires Windows 11 IoT Enterprise LTSC license
- Some settings can be tuned via GPO post-deployment

## Alternatives Considered

### Manual hardening per device
- Pros: Flexible per-device
- Why not: Not reproducible; audit nightmare; doesn't scale

### Microsoft Security Baseline
- Pros: Microsoft-provided, simpler
- Why not: Less comprehensive than CIS; CIS more recognized in defense

### STIG (DoD Security Technical Implementation Guide)
- Pros: Most rigorous, DoD-specific
- Why not: Overly restrictive for commercial manufacturing; CIS is sufficient for CMMC Level 2

### No hardening (vanilla Windows)
- Pros: Simplest
- Why not: Compliance requirement; customer expectation

## References
- [CIS Microsoft Windows 11 Enterprise Benchmark](https://www.cisecurity.org/benchmark/microsoft_windows_desktop)
- [NIST 800-171 Revision 2](https://csrc.nist.gov/publications/detail/sp/800-171/rev-2/final)
