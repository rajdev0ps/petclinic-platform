---
paths:
  - "docs/**/*.md"
---

# Documentation Rules

## Directory Structure

```
docs/
├── architecture.md          # System architecture, diagrams, component relationships
├── runbook.md               # Day-to-day operations: deploy, rollback, scale, restart
├── incident-playbook.md     # Incident response: escalation, RCA template, war room
├── onboarding.md            # New team member setup: tools, access, first deploy
├── monitoring-guide.md      # Dashboards, alerts, SLOs, where to look when paged
├── secret-rotation.md       # How to rotate each secret type safely
├── dr-plan.md               # Disaster recovery: RPO/RTO, failover, restore procedures
├── compliance-checklist.md  # Security controls, audit evidence, review cadence
└── adr/                     # Architecture Decision Records
    └── 0001-public-subnets.md  # All-public subnet design for cost optimization
```

## Writing Conventions

1. **Audience:** Internal DevOps/Cloud team who inherit this platform. Assume AWS + K8s familiarity.
2. **Tone:** Direct, actionable, no filler. Prefer commands over descriptions.
3. **Format:** Every doc MUST have:
   - Title (H1)
   - Last Updated date
   - Purpose (1-2 sentences)
   - Table of Contents (for docs > 3 sections)
4. **Code blocks:** Every command must be copy-pasteable. Include the full command, not fragments.
5. **Environment awareness:** Always specify which env (dev/prod) or use `{env}` placeholder.

## Runbook Format

Runbooks follow a strict format for each procedure:

```markdown
### Procedure: {name}

**When:** {trigger condition}
**Who:** {required role/access}
**Time:** {expected duration}

**Steps:**
1. {step with exact command}
2. {step with exact command}

**Verify:**
- {how to confirm success}

**Rollback:**
- {how to undo if it fails}
```

## ADR Format

Architecture Decision Records use the standard template:

```markdown
# ADR-{number}: {title}

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-{N}
**Date:** YYYY-MM-DD
**Context:** {what is the problem or decision to be made}
**Decision:** {what was decided and why}
**Consequences:** {positive and negative outcomes}
```

## Cross-References

- Reference Terraform modules by path: `terraform/modules/{module}/`
- Reference K8s manifests by path: `k8s/base/{service}/`
- Link to related ADRs when explaining "why" decisions
- Include Jira ticket IDs (PETPLAT-xxx) where applicable

## What NOT to Include

- No secrets, passwords, or API keys (even examples)
- No personal names or emails (use role names: "on-call engineer", "team lead")
- No internal URLs that won't work for the handover team
- No screenshots without alt text describing the content
