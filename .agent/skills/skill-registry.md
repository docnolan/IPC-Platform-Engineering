# IPC Platform Agent Skill Registry

Central registry of all agent skills available in the IPC Platform Digital Twin. Used by `fleet-conductor` for routing decisions.

## Active Skills

| Skill | Area | Pillar | Trigger Keywords |
|-------|------|--------|------------------|
| [fleet-conductor](#fleet-conductor) | Operations | Orchestration | new work, route, coordinate, dispatch |
| [platform-engineer](#platform-engineer) | Operations | Build | implement, create, build, configure, deploy, code |
| [knowledge-curator](#knowledge-curator) | Governance | Docs | document, wiki, readme, runbook, update docs |
| [compliance-auditor](#compliance-auditor) | Governance | Risk | compliance, nist, cmmc, audit, control, evidence |
| [release-ring-manager](#release-ring-manager) | Operations | Deploy | pipeline, build, deploy, release, promote, ci/cd |
| [drift-detection-analyst](#drift-detection-analyst) | Observability | State | drift, sync, flux, gitops, reconcile, out of sync |
| [site-reliability-engineer](#site-reliability-engineer) | Observability | Health | health, crash, restart, failing, down, logs, error |
| [telemetry-data-engineer](#telemetry-data-engineer) | Observability | Data | kql, query, dashboard, workbook, metrics, telemetry |
| [secret-rotation-manager](#secret-rotation-manager) | Governance | Risk | secret, credential, password, pat, token, rotate, expired |
| [architecture-governor](#architecture-governor) | Governance | Quality | review, pr, architecture, design, pattern, decision, adr |

---

## Skill Details

### fleet-conductor

**Role:** Central orchestrator for the agent fleet. Routes work to specialists.

**Location:** `.agent/skills/fleet-conductor/`

**Triggers:**
- New work request received
- Task requires multiple skills
- Unclear routing
- Coordination needed

**Never Does:** Execute implementation directly — always delegates

---

### platform-engineer

**Role:** Senior platform engineer for all implementation work. Handles Infrastructure-as-Code, containers, Kubernetes, pipelines, and automation.

**Location:** `.agent/skills/platform-engineer/`

**Triggers:**
- Implementation tasks assigned
- Keywords: implement, create, build, configure, deploy
- File types: `.ps1`, `.py`, `.go`, `.yaml`, `Dockerfile`, `.tf`, `.pkr.hcl`

**Expertise Areas:**
- Kubernetes and container orchestration
- Edge computing and hybrid cloud
- Virtualization (Hyper-V, VMware, KVM)
- Infrastructure-as-Code (Terraform, Packer)
- CI/CD pipelines and GitOps
- Observability stack (Prometheus, Grafana, Azure Monitor)
- Programming (PowerShell, Python, Go, Rust)

---

### knowledge-curator

**Role:** Maintains all project documentation. Ensures docs reflect current state.

**Location:** `.agent/skills/knowledge-curator/`

**Triggers:**
- Implementation complete (needs documentation)
- Keywords: document, wiki, readme, runbook
- Documentation identified as outdated

**Outputs:** Wiki pages, README files, runbooks, troubleshooting guides

---

### compliance-auditor

**Role:** Validates changes against NIST 800-171 and CMMC controls.

**Location:** `.agent/skills/compliance-auditor/`

**Triggers:**
- PRs touching security-relevant files
- Keywords: compliance, nist, cmmc, audit, evidence
- Changes to `packer/`, `compliance/`, hardening

**Outputs:** Compliance assessments, audit evidence, control mapping

---

### release-ring-manager

**Role:** Manages CI/CD pipelines and deployment promotion.

**Location:** `.agent/skills/release-ring-manager/`

**Triggers:**
- Pipeline creation/modification
- Build failures
- Keywords: pipeline, build, deploy, release, promote
- Changes to `pipelines/`

**Outputs:** Pipeline definitions, promotion approvals, build investigations

---

### drift-detection-analyst

**Role:** Monitors GitOps sync and detects configuration drift.

**Location:** `.agent/skills/drift-detection-analyst/`

**Triggers:**
- Flux sync errors
- Suspected manual cluster changes
- Keywords: drift, sync, flux, gitops, reconcile

**Outputs:** Drift reports, root cause analysis, remediation

---

### site-reliability-engineer

**Role:** Monitors workload health and responds to incidents.

**Location:** `.agent/skills/site-reliability-engineer/`

**Triggers:**
- Pod crashes or restarts
- Resource exhaustion alerts
- Keywords: health, crash, failing, down, error, logs

**Outputs:** Health assessments, incident response, remediation

---

### telemetry-data-engineer

**Role:** Develops KQL queries, dashboards, and alerting rules.

**Location:** `.agent/skills/telemetry-data-engineer/`

**Triggers:**
- Query development requests
- Dashboard creation
- Keywords: kql, query, dashboard, metrics, telemetry

**Outputs:** KQL queries, Azure Workbooks, alert rules

---

### secret-rotation-manager

**Role:** Manages credential lifecycle and secret rotation.

**Location:** `.agent/skills/secret-rotation-manager/`

**Triggers:**
- Credential expiration warnings
- Authentication failures
- Keywords: secret, credential, rotate, token, expired

**Outputs:** Rotated credentials, audit logs, inventory reports

---

### architecture-governor

**Role:** Final review authority for all platform changes.

**Location:** `.agent/skills/architecture-governor/`

**Triggers:**
- PRs ready for final review
- Architectural decisions needed
- Keywords: review, pr, architecture, design, adr

**Outputs:** Review decisions, ADRs, architectural guidance

---

## Routing Quick Reference

### By File Type

| Pattern | Primary Skill |
|---------|---------------|
| `*.ps1`, `*.py`, `*.go` | platform-engineer |
| `Dockerfile`, `kubernetes/**` | platform-engineer |
| `*.pkr.hcl`, `*.tf` | platform-engineer |
| `*.md` (docs) | knowledge-curator |
| `pipelines/*.yml` | release-ring-manager |
| `compliance/**` | compliance-auditor |

### By Keyword

| Keywords | Route To |
|----------|----------|
| implement, create, build, configure | platform-engineer |
| document, wiki, readme, runbook | knowledge-curator |
| audit, nist, cmmc, compliance | compliance-auditor |
| pipeline, build, deploy, release | release-ring-manager |
| drift, sync, flux, gitops | drift-detection-analyst |
| health, crash, failing, logs | site-reliability-engineer |
| kql, query, dashboard, metrics | telemetry-data-engineer |
| secret, credential, rotate, token | secret-rotation-manager |
| review, pr, architecture, design | architecture-governor |

---

## Common Workflows

### New Feature Implementation

```
fleet-conductor
    └─→ platform-engineer (implement)
        └─→ compliance-auditor (validate)
            └─→ knowledge-curator (document)
                └─→ architecture-governor (review)
```

### Incident Response

```
fleet-conductor
    └─→ site-reliability-engineer (triage)
        └─→ platform-engineer (fix if needed)
            └─→ knowledge-curator (postmortem)
```

### Credential Rotation

```
fleet-conductor
    └─→ secret-rotation-manager (rotate)
        └─→ release-ring-manager (if pipeline affected)
            └─→ drift-detection-analyst (verify sync)
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-27 | Initial 10-skill registry |
| 1.1 | 2025-01-28 | Renamed ipc-junior-engineer → platform-engineer |
