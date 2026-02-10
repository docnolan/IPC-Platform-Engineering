---
description: Standard workflow for implementing new features
---

# Feature Request Workflow

## 1. Review Requirements
- [ ] Understand the user request and business goal.
- [ ] Identify which components are affected.

## 2. Architecture Compliance Check
> [!IMPORTANT]
> You MUST check for existing Architecture Decision Records (ADRs) before designing validation.

- [ ] Check `docs/architecture/decisions/` for relevant standards.
- [ ] If a new pattern is needed, propose a new ADR using `ADR-0000-template.md`.

## 3. Design & Plan
- [ ] Create an implementation plan.
- [ ] Verify security implications (Refer to `compliance-auditor` standards).

## 4. Implementation
- [ ] Write code (Test-Driven Development preferred).
- [ ] Update documentation.

## 5. Verification
- [ ] Run automated tests.
- [ ] Verify against acceptance criteria.
