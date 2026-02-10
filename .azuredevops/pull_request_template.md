## Documentation Checklist

### Required for All PRs
- [ ] I have verified my changes do not break existing documentation
- [ ] Links in documentation are valid (no 404s)

### Required if Code Changes Affect User-Facing Behavior
- [ ] Wiki documentation updated to reflect changes
- [ ] Code examples in documentation tested and working
- [ ] A1-Troubleshooting.md updated if new failure modes introduced

### Required if New Component Added
- [ ] Component documented in appropriate wiki file
- [ ] README.md added to component directory
- [ ] Configuration options documented
- [ ] Required secrets/environment variables documented

### Required if Architectural Decision Made
- [ ] ADR created: `docs/architecture/decisions/ADR-NNNN-[title].md`
- [ ] ADR linked from relevant wiki documentation

### Compliance-Sensitive Changes
- [ ] 09-Compliance-as-a-Service.md updated if security-relevant
- [ ] Evidence queries updated if audit logging affected
- [ ] Risk register updated if CVE/vulnerability related
