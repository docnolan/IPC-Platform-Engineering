# Risk Register

| Risk ID | Severity | CVE Reference | Component | Description | Mitigation / Rationale | Status | Review Date |
|---------|----------|---------------|-----------|-------------|------------------------|--------|-------------|
| RR-001 | CRITICAL | CVE-2025-7458 | sqlite3 | Integer overflow in SQLite | **Accept Risk**: No fixed version available in Debian 12 (Stable) upstream. Exploitation requires local access/crafted db file, which is low risk for these containerized workloads. | Accepted | 2026-04-30 |
| RR-002 | HIGH | CVE-2023-45853 | zlib | Integer overflow in Minizip | **Accept Risk**: Marked "Will Not Fix" by Debian/Upstream maintainers. Issue is in "minizip" contrib package, not core zlib used by Python. | Accepted | 2026-04-30 |
