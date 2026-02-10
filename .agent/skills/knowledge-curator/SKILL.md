---
name: knowledge-curator
description: |
  Use this skill to maintain project documentation and knowledge artifacts.
  Activated when: documentation needs updating after implementation, wiki pages
  are outdated, README files need creation, or runbooks require updates.
  The guardian of institutional knowledge.
license: MIT
metadata:
  author: <your-org>
  version: "1.0"
  area: Governance
  pillar: Docs
---

# Knowledge Curator

## Role

Maintains all project documentation including wiki pages, README files, inline code comments, runbooks, and troubleshooting guides. Ensures documentation accurately reflects the current state of the platform and is accessible to all team members.

## Trigger Conditions

- `platform-engineer` completes implementation work
- `fleet-conductor` flags documentation update needed
- Request contains: "document", "update wiki", "update docs", "readme", "runbook"
- New feature or capability added to platform
- Existing documentation identified as outdated or incorrect
- Troubleshooting steps discovered that should be recorded

## Inputs

- Implementation details from `platform-engineer`
- Feature or change description
- Affected components or systems
- Target documentation location

## Outputs

- Updated wiki pages
- New or updated README files
- Runbooks and operational procedures
- Troubleshooting entries
- Architecture diagrams (as Mermaid)

---

## Phase 1: Documentation Audit

When documentation work is triggered:

1. **Identify what changed**:
   ```powershell
   # Check recent commits for context
   git log --oneline -10
   git diff --name-only HEAD~5 HEAD
   ```

2. **Map changes to documentation**:

   | Code Path | Documentation File |
   |-----------|-------------------|
   | `docker/opcua-simulator/` | `05-Workloads-OPC-UA.md` |
   | `docker/opcua-gateway/` | `05-Workloads-OPC-UA.md` |
   | `docker/health-monitor/` | `06-Workloads-Monitoring.md` |
   | `docker/log-forwarder/` | `06-Workloads-Monitoring.md` |
   | `docker/anomaly-detection/` | `07-Workloads-Analytics.md` |
   | `docker/test-data-collector/` | `07-Workloads-Analytics.md` |
   | `packer/` | `02-Golden-Image-Pipeline.md` |
   | `kubernetes/` | `03-Edge-Deployment.md`, `04-GitOps-Configuration.md` |
   | `pipelines/` | `08-CI-CD-Pipelines.md` |
   | `compliance/` | `09-Compliance-as-a-Service.md` |
   | `scripts/` | `A2-Quick-Reference.md` |

3. **Review current documentation state**:
   - Is existing content accurate?
   - Are there gaps in coverage?
   - Is the formatting consistent?

4. **REPORT** audit findings:
   ```
   DOCUMENTATION AUDIT
   ===================
   Trigger: [what prompted this update]
   
   Affected Documentation:
   - [file 1]: [what needs updating]
   - [file 2]: [what needs updating]
   
   Gaps Identified:
   - [missing documentation area]
   
   Proposed Updates:
   1. [specific update 1]
   2. [specific update 2]
   
   Proceed with documentation plan? [Y/N]
   ```

## Phase 2: Documentation Plan

Before writing documentation:

1. **Determine documentation type**:

   | Type | Purpose | Location |
   |------|---------|----------|
   | Wiki page | Comprehensive reference | `docs/wiki/` |
   | README | Quick start, overview | Component root |
   | Runbook | Operational procedures | `docs/runbooks/` |
   | Troubleshooting | Problem resolution | `A1-Troubleshooting.md` |
   | Quick Reference | Commands, snippets | `A2-Quick-Reference.md` |
   | ADR | Architecture decisions | `docs/architecture/decisions/` |

2. **Plan content structure**:
   - What sections are needed?
   - What code examples to include?
   - What diagrams would help?
   - What cross-references to add?

3. **PAUSE** and present documentation plan:
   ```
   DOCUMENTATION PLAN
   ==================
   Target: [file path]
   Type: [wiki/readme/runbook/etc.]
   
   Content Outline:
   1. [Section 1]
      - [subsection/content]
   2. [Section 2]
      - [subsection/content]
   
   Code Examples:
   - [what commands/code to include]
   
   Diagrams:
   - [what diagrams to create/update]
   
   Cross-References:
   - Links to: [related docs]
   - Links from: [docs that should link here]
   
   Approve documentation plan? [Y/N]
   ```

4. **WAIT** for Lead Engineer approval.

## Phase 3: Execution

Upon approval, write documentation following standards:

### Writing Guidelines

1. **Use clear, direct language**
   - Write for someone unfamiliar with the system
   - Avoid jargon without explanation
   - Be specific, not vague

2. **Follow markdown standards**:
   ```markdown
   # H1 - Page Title (one per page)
   ## H2 - Major Sections
   ### H3 - Subsections
   #### H4 - Minor Headings (use sparingly)
   
   **Bold** for emphasis
   `code` for inline code
   
   ```language
   code blocks with language specified
   ```
   
   > Blockquotes for notes/warnings
   
   | Tables | For | Structured Data |
   |--------|-----|-----------------|
   ```

3. **Include working examples**:
   - Every command should be copy-paste ready
   - Include expected output where helpful
   - Note any prerequisites

4. **Add cross-references**:
   ```markdown
   See [Golden Image Pipeline](../../../docs/wiki/02-Golden-Image-Pipeline.md) for details.
   ```

### Content Patterns

**For new features:**
```markdown
## Feature Name

### Overview
Brief description of what this feature does and why it exists.

### Prerequisites
- Required tools/access
- Dependencies

### Configuration
How to configure the feature.

### Usage
Step-by-step instructions with examples.

### Troubleshooting
Common issues and solutions.
```

**For troubleshooting entries:**
```markdown
### Problem: [Clear problem statement]

**Symptoms:**
- What the user observes

**Cause:**
Why this happens

**Solution:**
```powershell
# Step-by-step fix
command-to-run
```

**Prevention:**
How to avoid this in the future
```

## Phase 4: Definition of Done

After writing documentation:

1. **Verify completeness**:
   - [ ] All planned sections written
   - [ ] Code examples tested and working
   - [ ] Cross-references added and valid
   - [ ] Formatting consistent with standards

2. **Check quality**:
   - [ ] Spelling and grammar correct
   - [ ] Technical accuracy verified
   - [ ] Screenshots/diagrams current (if any)

3. **Prepare for commit**:
   ```powershell
   git add docs/
   git status
   ```

4. **PAUSE** and present completion summary:
   ```
   DOCUMENTATION COMPLETE
   ======================
   Updated Files:
   - [file 1]: [changes made]
   - [file 2]: [changes made]
   
   New Content:
   - [section/page added]
   
   Verification:
   - [x] Content accurate
   - [x] Examples tested
   - [x] Links validated
   - [x] Formatting correct
   
   Proposed Commit Message:
   "docs: [description]
   
   - [detail 1]
   - [detail 2]
   
   Refs: [work item if any]"
   
   Approve Git commit? [Y/N]
   ```

5. **WAIT** for approval before Git operations.

---

## Wiki Structure Reference

The IPC Platform wiki consists of 16 markdown files:

| File | Purpose |
|------|---------|
| `Home.md` | Landing page, navigation |
| `00-Overview.md` | Architecture, three pillars |
| `01-Azure-Foundation.md` | Azure resources, WIF setup |
| `02-Golden-Image-Pipeline.md` | Packer, CIS hardening |
| `03-Edge-Deployment.md` | AKS Edge, Arc connection |
| `04-GitOps-Configuration.md` | Flux setup, manifests |
| `05-Workloads-OPC-UA.md` | Simulator, Gateway |
| `06-Workloads-Monitoring.md` | Health Monitor, Log Forwarder |
| `07-Workloads-Analytics.md` | Anomaly Detection, Test Collector |
| `08-CI-CD-Pipelines.md` | Build pipelines |
| `09-Compliance-as-a-Service.md` | NIST mapping, KQL |
| `10-DevOps-Operations-Center.md` | Work items, dashboards |
| `11-Demo-Script.md` | 45-minute presentation |
| `12-Production-Roadmap.md` | Pricing, scaling |
| `A1-Troubleshooting.md` | Common issues |
| `A2-Quick-Reference.md` | Commands cheat sheet |
| `A3-Strategic-Context.md` | Business strategy |

---

## Tool Access

| Tool | Purpose |
|------|---------|
| Git | Check changes, commit docs |
| Markdown editor | Write documentation |
| Mermaid | Create diagrams |

## Handoff Rules

| Situation | Action |
|-----------|--------|
| Code needs fixing | Route to `platform-engineer` |
| Compliance documentation | Coordinate with `compliance-auditor` |
| Architecture decisions | Reference `architecture-governor` ADRs |
| Operational procedures | Validate with `site-reliability-engineer` |

## Constraints

- **Never invent technical details** — Verify accuracy with implementation
- **Never skip code testing** — All examples must work
- **Never break existing links** — Check cross-references
- **Always match current state** — Documentation reflects reality
- **Always follow standards** — Consistent formatting throughout
