# Media Protection Policy
**Control ID:** NIST 3.8.1
**Effective Date:** 2026-02-04
**Scope:** All portable and fixed data storage media.

## Policy Statement
The Company ensures the security of organizational information by controlling access to, and use of, system media, and by securely sanitizing or destroying media before disposal.

## Requirements

### 1. Encryption
- **Control 3.13.11**: Employ FIPS-validated cryptography for protecting confidentiality.
- **Implementation**:
    - All local hard drives must be encrypted using BitLocker (AES-256).
    - Portable media (USB drives) must be encrypted if used to transport CUI.

### 2. Media Access and Transport
- Access to digital media is restricted to authorized personnel.
- Media containing CUI must be protected during transport and must not be left unattended in unsecured areas.

### 3. Media Sanitization
- **Control 3.8.3**: Sanitize or destroy system media containing Federal Contract Information (FCI) before disposal or release for reuse.
- **Implementation**:
    - Media must be wiped using NIST 800-88 compliant tools (e.g., Secure Erase) before decommissioning.
    - If wiping is not possible, physical destruction (shredding/degaussing) is required.

## Enforcement
Violations of this policy may result in disciplinary action up to and including termination of employment.
