---
name: review-terraform
description: Review Terraform code for security, best practices, and conventions
argument-hint: "[path]"
---

# /review-terraform [path]

Review Terraform code against the project's security requirements, naming conventions, and best practices.

## Arguments

- `path` — Path to review: a module directory, environment, or specific file
- Default: `terraform/` (entire Terraform codebase)

## Steps

1. Read the target files:
   - If `path` is a directory, glob for all `.tf` files within it
   - If `path` is a file, read that specific file

2. Check against the project's Terraform conventions (from CLAUDE.md and rules):

   **Naming:**
   - Resource names follow `petclinic-{env}-{resource}` pattern
   - Terraform identifiers use snake_case
   - Module variables and outputs are descriptive

   **Structure:**
   - Module has main.tf, variables.tf, outputs.tf, versions.tf
   - Variables have `description` and `type`
   - Outputs export useful downstream values

   **Security:**
   - No hardcoded secrets
   - IAM follows least privilege
   - Encryption enabled on all storage
   - No public access to internal resources
   - Security groups are restrictive
   - Sensitive outputs marked `sensitive = true`

   **Tags:**
   - Every taggable resource has Project, Environment, ManagedBy tags

   **Best Practices:**
   - No deprecated resources or arguments
   - Provider version constraints in versions.tf
   - Backend config uses S3 + DynamoDB locking

3. Present findings in a structured format:
   ```
   ## Terraform Review: {path}

   ### Issues Found
   - [SECURITY] {description} — {file}:{line}
   - [NAMING] {description} — {file}:{line}
   - [MISSING] {description} — {file}:{line}

   ### Good Practices Observed
   - {What's done well}

   ### Summary
   Files reviewed: N | Issues: N (critical: N, warning: N, info: N)
   ```

## Important

- This is a review — it reads code but does not modify it
- Focus on actionable findings, not style nitpicks
- Reference specific files and line numbers
- Prioritize security issues over naming conventions
