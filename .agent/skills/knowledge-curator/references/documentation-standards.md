# Documentation Standards

Reference document defining the structure, style, and conventions for all IPC Platform documentation.

## Wiki Structure

The project wiki consists of 16 markdown files organized by topic:

| File | Purpose | Update Frequency |
|------|---------|------------------|
| 00-Overview.md | Architecture, pillars, high-level summary | When architecture changes |
| 01-Azure-Foundation.md | Azure resources, WIF, subscriptions | When Azure resources change |
| 02-Golden-Image-Pipeline.md | Packer templates, CIS hardening | When image build changes |
| 03-Edge-Deployment.md | AKS Edge, Arc connection | When edge config changes |
| 04-GitOps-Configuration.md | Flux setup, repo structure | When GitOps changes |
| 05-Workloads-OPC-UA.md | Simulator and Gateway workloads | When OPC-UA workloads change |
| 06-Workloads-Monitoring.md | Health monitor, Log forwarder | When monitoring changes |
| 07-Workloads-Analytics.md | Anomaly detection, Test collector | When analytics change |
| 08-CI-CD-Pipelines.md | Azure DevOps pipelines | When pipelines change |
| 09-Compliance-as-a-Service.md | NIST mapping, KQL queries | When compliance logic changes |
| 10-DevOps-Operations-Center.md | Work items, dashboards | When DevOps practices change |
| 11-Demo-Script.md | Presentation flow, talking points | Before demos |
| 12-Production-Roadmap.md | Phases, pricing, scaling | When roadmap evolves |
| A1-Troubleshooting.md | Common issues and fixes | When new issues discovered |
| A2-Quick-Reference.md | Commands cheat sheet | When commands change |
| A3-Strategic-Context.md | Business strategy, market analysis | Rarely |

## Markdown Formatting Standards

### Heading Hierarchy

```markdown
# Page Title (H1) - One per page

## Major Section (H2)

### Subsection (H3)

#### Detail Section (H4) - Use sparingly
```

### Code Blocks

Always specify the language for syntax highlighting:

````markdown
```powershell
# PowerShell code
Get-Process
```

```yaml
# YAML configuration
apiVersion: v1
kind: ConfigMap
```

```python
# Python code
print("Hello")
```

```bash
# Bash/shell commands
kubectl get pods
```

```kql
// KQL queries
IPCHealthMonitor_CL
| where TimeGenerated > ago(1h)
```
````

### Tables

Use tables for structured reference data:

```markdown
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Data 1   | Data 2   | Data 3   |
| Data 4   | Data 5   | Data 6   |
```

### Admonitions/Callouts

Use blockquotes for important notes:

```markdown
> **Note:** Important information the reader should know.

> **Warning:** Potential issues or dangers.

> **Tip:** Helpful suggestions.
```

### Internal Links

Link to other wiki pages using relative paths:

```markdown
See [Azure Foundation](../../../../docs/wiki/01-Azure-Foundation.md) for details.

Related: [Troubleshooting](../../../../docs/wiki/A1-Troubleshooting.md)
```

### Content Guidelines

### Voice and Tone

- **Direct and instructional**: "Run the following command" not "You might want to run"
- **Second person**: "You will see" or imperative "Configure the setting"
- **Technical but accessible**: Explain acronyms on first use
- **Consistent terminology**: Use the same terms throughout (e.g., always "IPC" not sometimes "panel")

### Command Documentation

When documenting commands:

1. Show the complete command (copy-paste ready)
2. Explain what it does
3. Show expected output where helpful
4. Note any prerequisites

```markdown
### Check Cluster Status

Run on the VM to verify the Kubernetes cluster is healthy:

```powershell
kubectl get nodes
```

Expected output:
```
NAME                   STATUS   ROLES                  AGE   VERSION
<device-id>-ledge   Ready    control-plane,master   Xd    v1.28.X
```

If status shows `NotReady`, see [Troubleshooting](../../../../docs/wiki/A1-Troubleshooting.md#node-not-ready).
```

### File Path Documentation

Always use consistent path formats:

- **Windows paths**: `C:\Projects\IPC-Platform-Engineering\`
- **Relative paths in repo**: `./kubernetes/workloads/`
- **Kubernetes paths**: `/app/config.yaml`

### Configuration Documentation

When documenting configuration:

1. Show the complete file
2. Explain key fields
3. Note what can be customized

```markdown
### Deployment Configuration

**File:** `kubernetes/workloads/health-monitor/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-monitor
  # ... rest of file
```

| Field | Purpose | Customizable |
|-------|---------|--------------|
| `replicas` | Number of instances | Yes |
| `image` | Container image | Via pipeline |
| `resources.limits` | Max CPU/memory | Yes |
```

## Section Templates

### New Workload Documentation

```markdown
## [Workload Name]

### Purpose

Brief description of what this workload does and why it exists.

### Architecture

How this workload fits into the overall system.

### File Locations

| File | Path |
|------|------|
| Dockerfile | `docker/<workload>/Dockerfile` |
| Python source | `docker/<workload>/src/<script>.py` |
| K8s deployment | `kubernetes/workloads/<workload>/deployment.yaml` |

### Configuration

Environment variables and settings.

### Verification

How to confirm the workload is running correctly.

### Troubleshooting

Common issues specific to this workload.
```

### New Troubleshooting Entry

```markdown
### [Problem Title]

**Symptom:** What the user observes.

**Cause:** Why this happens.

**Solution:**
```powershell
# Commands to fix the issue
```

**Prevention:** How to avoid this in the future.
```

## Cross-Reference Patterns

### Related Pages Section

Every page should end with related links:

```markdown
---

## Related Pages

- [Page Name](XX-Page-Name.md) — Brief reason to visit
- [Another Page](XX-Another.md) — Brief reason to visit
```

### Navigation Headers

Major pages include navigation:

```markdown
**Previous:** [XX-Previous-Page.md](XX-Previous-Page.md)  
**Next:** [XX-Next-Page.md](XX-Next-Page.md)
```

## Update Checklist

When updating documentation, verify:

- [ ] All code examples are accurate and tested
- [ ] All file paths exist and are correct
- [ ] All internal links work
- [ ] Tables are properly formatted
- [ ] Heading hierarchy is consistent
- [ ] Related pages section is updated
- [ ] No orphaned references to removed content
