---
name: terraform-apply
description: Apply a saved Terraform plan with safety checks
disable-model-invocation: true
argument-hint: "[env]"
---

# /terraform-apply [env]

Apply a previously saved Terraform plan for the specified environment.

## Arguments

- `env` — Target environment: `dev` or `prod` (default: `dev`)

## Steps

1. Determine the environment directory:
   - `dev` → `terraform/environments/dev/`
   - `prod` → `terraform/environments/prod/`

2. Check that `plan.out` exists in the environment directory:
   ```bash
   ls -la terraform/environments/{env}/plan.out
   ```
   If it doesn't exist, tell the user to run `/terraform-plan {env}` first.

3. Show the plan summary by running:
   ```bash
   cd terraform/environments/{env} && terraform show plan.out
   ```

4. Ask the user for explicit confirmation before applying:
   - Show: "About to apply plan to **{env}** environment. This will modify AWS resources."
   - For **prod**: Add extra warning: "This is PRODUCTION. Changes will affect live services."

5. Only after user confirms, apply the saved plan:
   ```bash
   cd terraform/environments/{env} && terraform apply plan.out
   ```

6. After apply completes, show:
   - Resources created/changed/destroyed
   - Key outputs (VPC ID, EKS endpoint, RDS endpoint, etc.)
   - Clean up: note that plan.out is consumed and a new plan is needed for future changes

## Important

- NEVER apply without a saved plan file
- NEVER use `-auto-approve`
- Always get explicit user confirmation, especially for prod
- If apply fails, show the error and do NOT retry automatically
