# Skill Registry

Reference document listing all skills in the IPC Platform agent fleet.

## Active Skills (Option A)

| Skill | Area | Pillar | Primary Responsibility |
|-------|------|--------|------------------------|
| fleet-conductor | Orchestration | Coordination | Routes work, resolves conflicts, aggregates status |
| ipc-junior-engineer | Operations | Build | Writes IaC, Config-as-Code, executes backlog tasks |
| knowledge-curator | Governance | Docs | Updates wiki and documentation to match code |
| compliance-auditor | Governance | Risk | Validates changes against NIST/CMMC controls |
| release-ring-manager | Operations | Deploy | Manages CI/CD pipelines and deployment promotion |
| drift-detection-analyst | Observability | State | Monitors GitOps sync, detects manual changes |
| site-reliability-engineer | Observability | Health | Monitors SLIs/SLOs, writes remediation scripts |
| telemetry-data-engineer | Observability | Data | Manages Log Analytics, KQL queries, dashboards |
| secret-rotation-manager | Governance | Crypto | Rotates credentials, manages Key Vault |
| architecture-governor | Governance | Strategy | Reviews PRs for patterns and technical debt |

## Routing Quick Reference

### Implementation Work

- New files, scripts, manifests → `ipc-junior-engineer`
- Pipeline YAML changes → `release-ring-manager`
- Documentation updates → `knowledge-curator`

### Validation Work

- Compliance checks → `compliance-auditor`
- PR reviews → `architecture-governor`
- Drift detection → `drift-detection-analyst`

### Operations Work

- Health monitoring → `site-reliability-engineer`
- Query/dashboard work → `telemetry-data-engineer`
- Credential issues → `secret-rotation-manager`

### Escalation Triggers

- Ambiguous scope → Lead Engineer
- Cross-cutting concerns (3+ skills) → Lead Engineer
- Production incidents → Lead Engineer + `site-reliability-engineer`
- Security vulnerabilities → Lead Engineer + `compliance-auditor`

## Workflow Sequences

### Standard PR Workflow

1. `ipc-junior-engineer` → implements change
2. `knowledge-curator` → updates documentation
3. `compliance-auditor` → validates controls
4. `architecture-governor` → reviews PR
5. `release-ring-manager` → merges and deploys

### Incident Response

1. `site-reliability-engineer` → triage and initial response
2. `drift-detection-analyst` → check for configuration drift
3. `ipc-junior-engineer` → implement fix
4. `knowledge-curator` → document resolution

### Credential Rotation

1. `secret-rotation-manager` → generate new credential
2. `ipc-junior-engineer` → update consuming resources
3. `drift-detection-analyst` → verify GitOps sync
