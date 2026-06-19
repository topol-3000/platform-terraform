# Coding Conventions

**Analysis Date:** 2026-06-19

## Naming Patterns

**Variables:**
- `snake_case` throughout — e.g., `name_prefix`, `state_bucket_name`, `noncurrent_version_expiration_days`, `tenant_domain`
- Descriptive names that reflect the resource or setting, not abbreviated

**Outputs:**
- `snake_case`, named to reflect the resource attribute exposed — e.g., `state_bucket_name`, `state_bucket_arn`, `cluster_arn`, `listener_arn`, `hosted_zone_id`
- Root env outputs include a cross-reference note in the description indicating the downstream consumer (see `envs/prod/outputs.tf`)

**Locals:**
- `snake_case` — e.g., `name_prefix`
- Defined at the top of `main.tf`, not spread across files

**Resources:**
- Resource label matches the logical role, not the resource type — e.g., `aws_s3_bucket.tfstate` (label is `tfstate`, not `bucket`)
- Supporting resources for the same logical object share the same label — e.g., `aws_s3_bucket.tfstate`, `aws_s3_bucket_versioning.tfstate`, `aws_s3_bucket_server_side_encryption_configuration.tfstate`, `aws_s3_bucket_public_access_block.tfstate`
- See `bootstrap/main.tf` for the canonical example of this pattern

**Modules (call site):**
- `snake_case` — e.g., `module "networking"`, `module "rds_tenant"`, `module "rds_proxy"`, `module "rds_control_plane"`
- Multi-word module names with hyphens in their directory names (`rds-control-plane`) are called with underscores (`rds_control_plane`)

**Files:**
- All `.tf` files use lowercase, no hyphens in filenames
- Standard file set per root/module: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (root configs also add `backend.tf`, `providers.tf`)
- Module directories use hyphens — e.g., `rds-control-plane/`, `rds-tenant/`

**Tags (AWS resource tags):**
- Applied exclusively via the provider-level `default_tags` block — no per-resource `tags = {}` blocks
- Tag key names use PascalCase: `Project`, `Environment`, `ManagedBy`, `Repo`, `Component`
- Tag values are string literals or variable references, not interpolated expressions
- `ManagedBy = "terraform"` is required on every provider block
- See `bootstrap/versions.tf` and `envs/prod/providers.tf` for the two provider definitions

## Code Style

**Formatting:**
- `terraform fmt -recursive` (run via `make fmt`) — this is the canonical formatter, no additional config file
- Attribute alignment uses spaces to align `=` signs within a block (standard `terraform fmt` output)

**Linting:**
- No `.tflint.hcl` or other linter config detected in the repo
- No pre-commit hooks detected
- Validation is performed manually via `make validate` (`terraform validate`)

## File Organization Within a Config

**Standard file set for a root config (`envs/prod`):**
- `backend.tf` — backend block only; no resources
- `providers.tf` — provider block with `default_tags`; no resources
- `versions.tf` — `terraform {}` block with `required_version` and `required_providers`
- `variables.tf` — all input variables
- `outputs.tf` — all root-level outputs (commented out until their module lands)
- `main.tf` — `locals` block + module calls (commented out until implemented)

**Standard file set for a module (`modules/*`):**
- `variables.tf` — all input variables
- `outputs.tf` — all outputs (commented out / empty until implemented)
- `main.tf` — all resources and data sources

**No versions.tf in modules** — version constraints live in root configs and `bootstrap/` only.

## Description Conventions

**Single-line descriptions:**
- End with a period
- State what the variable/output IS or does, not how to use it
- Example: `"Prefix for resource names, e.g. \"odoo-saas-prod\"."`

**Multi-line descriptions:**
- Use `<<-EOT` heredoc syntax
- Used when context or usage guidance requires more than one sentence
- Example: `bootstrap/variables.tf` `state_bucket_name` and `envs/prod/variables.tf` `tenant_domain`

**Output descriptions (root env):**
- Include the downstream consumer mapping: `"<What it is> -> provisioner \`<setting_name>\`."`
- See the commented-out outputs in `envs/prod/outputs.tf` for the pattern

## Variable Defaults

- Provide defaults for variables that have a sensible project-wide value (region, project, environment)
- Leave no default (or default to `""`) for variables that MUST be set per-deployment (e.g., `tenant_domain`)
- Inline comment `# TODO: set in terraform.tfvars before building <module>` marks required-but-empty defaults

## Module Interface Pattern

Every module accepts exactly one required variable at scaffold time:

```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}
```

Additional variables are added as the module is implemented. The `name_prefix` is always derived from the env's `locals` block:

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"
}
```

See `envs/prod/main.tf` for the call-site pattern.

## Comments

**Module header block (`main.tf`):**
```
# Module: <name>
# Purpose: <one-line description>
#
# SEED-001 note: <design decision / constraint>
#
# STATUS: stub. No resources yet.
# See <path to seed doc>
#
# TODO: implement <purpose>
```
See any `modules/*/main.tf` for the exact format.

**Section separators in `envs/prod/main.tf`:**
```
# --- <N>. <Section title> --------------------------------
```
Used to delineate the ordered build sequence within the root config.

**When to comment:**
- Every non-obvious resource gets a single-line comment above it explaining WHY, not WHAT
- See `bootstrap/main.tf` — comments explain intent (e.g., "State is the source of truth... guard against accidental `terraform destroy`")
- Inline comments on individual attributes are used sparingly and only to explain non-obvious values

**TODO comments:**
- Format: `# TODO: <imperative action>`
- Include inline on the relevant attribute or at the top of stub `main.tf` files

## Error Handling / Validation

- No `validation {}` blocks present in any variable as of this analysis
- No `precondition` / `postcondition` lifecycle blocks
- No `sensitive = true` annotations on outputs
- Input protection relies on type constraints (`string`, `number`) and the absence of defaults for required values

## State and Lifecycle

**`prevent_destroy = true`** on `aws_s3_bucket.tfstate` in `bootstrap/main.tf` — the only lifecycle block in the codebase. Apply to any foundational resource that is impractical to recreate.

**Remote state:** S3 backend with `use_lockfile = true` (Terraform ≥ 1.11 native locking). No DynamoDB.

**State isolation:** Each environment uses a unique backend `key`. Workspaces are not used.

---

*Convention analysis: 2026-06-19*
