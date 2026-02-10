# Review Standards

Comprehensive standards for code review, architecture review, and approval processes in the IPC Platform.

## Review Categories

| Category | File Patterns | Review Depth | SLA |
|----------|---------------|--------------|-----|
| **Documentation** | `*.md`, `docs/**` | Light | Same day |
| **Configuration** | `*.yaml`, `*.json`, `*.toml` | Medium | 1 business day |
| **Infrastructure** | `kubernetes/**`, `packer/**`, `pipelines/**` | Deep | 2-3 business days |
| **Application Code** | `docker/*/src/**`, `*.py`, `*.ps1`, `*.go` | Deep | 2-3 business days |
| **Security** | Hardening, RBAC, secrets, auth | Critical | 3-5 business days |
| **Architecture** | New patterns, major dependencies | Critical | 1 week+ |

---

## Architectural Principles

All changes must align with these principles:

### 1. GitOps is Source of Truth
- All configuration lives in Git
- No manual cluster changes (Shadow IT)
- Declarative over imperative
- **Block**: Direct kubectl edits to production, undocumented configurations

### 2. Security by Default
- Hardened baselines (CIS benchmarks)
- Least privilege access
- Defense in depth
- **Block**: Disabled TLS, default credentials, overly permissive rules

### 3. Compliance is Non-Negotiable
- Changes must not break compliance posture
- Audit trail must be preserved
- Evidence collection is automated
- **Block**: Disabled audit logging, weakened access controls

### 4. Observability First
- Everything is logged appropriately
- Metrics for key indicators
- Alerts for anomalies
- **Block**: Missing logging, swallowed exceptions, no health checks

### 5. Fail Safe
- Graceful degradation on errors
- No data loss on failure
- Recovery is automated where possible
- **Block**: Crash on error, data corruption risk, no rollback path

### 6. Simplicity Over Cleverness
- Straightforward solutions preferred
- Complexity must be justified
- Maintainability is paramount
- **Block**: Over-engineered solutions, unnecessary abstractions

---

## Code Review Standards

### PowerShell (*.ps1)

| Requirement | Check |
|-------------|-------|
| Approved verbs | `Get-Verb` for valid verbs |
| Parameter validation | `[Parameter()]`, `[ValidateSet()]` |
| Error handling | `try/catch` blocks |
| Help documentation | `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE` |
| Logging | `Write-Verbose`, `Write-Error` (not `Write-Host`) |
| No hardcoded secrets | Scan for credentials |

```powershell
# Good pattern
function Get-Something {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    
    try {
        # Implementation
    }
    catch {
        Write-Error "Failed to get something: $_"
        throw
    }
}
```

### Python (*.py)

| Requirement | Check |
|-------------|-------|
| Type hints | Function signatures have types |
| Docstrings | Module, class, function documentation |
| Error handling | `try/except` with specific exceptions |
| Logging | `logging` module (not `print()`) |
| No hardcoded secrets | Scan for credentials |

```python
# Good pattern
def get_something(name: str) -> Optional[dict]:
    """Get something by name.
    
    Args:
        name: The name to look up.
        
    Returns:
        Dictionary with results, or None if not found.
        
    Raises:
        ValueError: If name is empty.
    """
    try:
        # Implementation
        return result
    except SpecificException as e:
        logger.error(f"Failed to get {name}: {e}")
        raise
```

### Dockerfile

| Requirement | Check |
|-------------|-------|
| Pinned base image | Specific tag, not `:latest` |
| Non-root user | `USER` directive present |
| Health check | `HEALTHCHECK` instruction |
| Minimal layers | Combined `RUN` commands |
| No secrets in image | No `ENV` with credentials |
| `.dockerignore` | Excludes unnecessary files |

```dockerfile
# Good pattern
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

RUN useradd --create-home appuser
USER appuser

HEALTHCHECK --interval=30s --timeout=10s \
    CMD python -c "import sys; sys.exit(0)"

ENTRYPOINT ["python", "src/main.py"]
```

### Kubernetes Manifests (*.yaml)

| Requirement | Check |
|-------------|-------|
| Standard labels | `app.kubernetes.io/*` labels present |
| Resource limits | `resources.requests` and `resources.limits` |
| Security context | `runAsNonRoot`, `readOnlyRootFilesystem` |
| Image pull policy | `IfNotPresent` or `Always` (not missing) |
| Liveness/readiness probes | Health endpoints configured |
| No `latest` tag | Specific image tags |

```yaml
# Good pattern
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-name
  labels:
    app.kubernetes.io/name: workload-name
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/managed-by: flux
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: workload-name
          image: registry/image:1.0.0
          imagePullPolicy: IfNotPresent
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "200m"
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
```

---

## Decision Authority Matrix

| Decision Type | Authority | Escalation |
|---------------|-----------|------------|
| Code style/formatting | Any reviewer | None |
| Bug fixes | Platform Engineer | Lead if risky |
| New features | Platform Engineer | Lead for architecture |
| Security changes | Lead Engineer (mandatory) | N/A |
| New dependencies | Lead Engineer | N/A |
| Architecture changes | Lead Engineer + ADR | N/A |
| Breaking changes | Lead Engineer + ADR | N/A |
| Technology choices | Lead Engineer + ADR | N/A |

---

## Architecture Decision Records (ADRs)

### When Required

- Introducing new technology or framework
- Changing fundamental patterns
- Making trade-offs with long-term impact
- Choosing between significant alternatives
- Deprecating existing approaches

### ADR Template

```markdown
# ADR-NNNN: [Short Title]

## Status
[Proposed | Accepted | Deprecated | Superseded by ADR-XXXX]

## Context
[What is the issue that motivates this decision?]

## Decision
[What is the change we're proposing?]

## Consequences

### Positive
- [benefit]

### Negative
- [drawback]

## Alternatives Considered
[What else was evaluated and why not chosen]

## References
[Links to relevant documentation]
```

### ADR Lifecycle

1. **Proposed** - Draft created, under discussion
2. **Accepted** - Decision made, implementation proceeds
3. **Deprecated** - No longer recommended but still valid
4. **Superseded** - Replaced by newer ADR

### ADR Location

```
docs/architecture/decisions/
├── ADR-0001-gitops-with-flux.md
├── ADR-0002-aks-edge-essentials.md
├── ADR-0003-workload-identity-federation.md
└── ADR-template.md
```

---

## Merge Requirements

Before any PR can be merged:

1. **All blocking issues resolved** - No unaddressed critical feedback
2. **Required reviewers approved** - Based on change category
3. **CI/CD pipeline passed** - All automated checks green
4. **Branch is up to date** - Rebased on main
5. **Work item linked** - Traceability maintained

### Merge Strategy

| Change Type | Strategy | Rationale |
|-------------|----------|-----------|
| Feature branches | Squash merge | Clean history |
| Release branches | Merge commit | Preserve history |
| Hotfixes | Squash merge | Single commit |

### Post-Merge

- Delete source branch
- Verify CI passes on main
- Monitor Flux sync (if K8s changes)
- Update work item status

---

## Review Checklist Templates

### Quick Review (Documentation/Config)

```
[ ] Changes are accurate
[ ] Formatting is correct
[ ] No sensitive data exposed
[ ] Links are valid
```

### Standard Review (Code)

```
[ ] Logic is correct
[ ] Error handling present
[ ] Logging appropriate
[ ] Tests included/updated
[ ] No hardcoded secrets
[ ] Follows conventions
[ ] Documentation updated
```

### Deep Review (Infrastructure/Security)

```
[ ] All Standard Review items
[ ] Security implications assessed
[ ] Compliance impact evaluated
[ ] Rollback plan exists
[ ] Performance impact considered
[ ] Dependencies justified
[ ] ADR created if needed
```
