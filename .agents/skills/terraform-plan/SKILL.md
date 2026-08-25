---
name: terraform-plan
description: Run terraform init + plan for an environment and show summary
disable-model-invocation: true
argument-hint: "[env]"
---

# /terraform-plan [env]

Run Terraform init and plan for the specified environment.

## Arguments

- `env` — Target environment: `dev` or `prod` (default: `dev`)

## Steps

1. Determine the environment directory:
   - `dev` → `terraform/environments/dev/`
   - `prod` → `terraform/environments/prod/`

2. Run `terraform init` in the environment directory:
   ```bash
   cd terraform/environments/{env} && terraform init
   ```

3. Run `terraform plan` and save the plan:
   ```bash
   cd terraform/environments/{env} && terraform plan -out plan.out
   ```

4. Show a summary of the plan output:
   - Resources to add, change, destroy
   - Any warnings or errors
   - Highlight any resources being destroyed (these need careful review)

5. If the plan shows destroys, warn the user explicitly:
   ```
   WARNING: This plan will DESTROY {N} resource(s). Review carefully before applying.
   ```

## Important

- Always use `-out plan.out` so the exact plan can be applied later
- Never run apply automatically — this skill only plans
- If init fails, show the error and suggest fixes (missing backend, provider issues)
