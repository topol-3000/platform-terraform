<!-- GSD:project-start source:PROJECT.md -->
## Project

**platform-terraform**

Terraform for the **shared AWS baseline** of the Odoo Entitlements SaaS platform. It provisions the long-lived, fleet-wide resources (networking, container platform, databases, routing/TLS, secrets) that the `provisioner` worker's `AwsDeploymentAdapter` assumes already exist before it creates *per-tenant* resources. The target architecture is locked in `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md`: **ECS/Fargate + one shared RDS PostgreSQL (database-per-tenant)**, chosen for cost-effectiveness and low maintenance.

**Core Value:** `terraform` in `envs/prod` produces a correct, well-formed plan for the shared AWS baseline — every module the provisioner depends on is implemented, wired, and exports the identifiers the `AwsDeploymentAdapter` needs.

### Constraints

- **Tech stack**: Terraform ≥ 1.11 (required for native S3 state locking), AWS provider `~> 6.0`. No DynamoDB lock table.
- **Architecture**: All module wiring done in `envs/prod/main.tf`; modules never call other modules. Every resource name prefixed with `var.name_prefix`. Secrets only ever via `modules/ssm` SecureStrings, never in plaintext outputs/state.
- **Cost**: No NAT gateway; Single-AZ tenant RDS at MVP; SSM Parameter Store over Secrets Manager. Cost-stripping is a locked SEED-001 theme.
- **Verification**: Code-complete only this milestone — `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan`. No `terraform apply`.
- **Region**: `eu-central-1` default (hardcoded in `envs/prod/backend.tf`, defaulted in tfvars).
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- HCL (HashiCorp Configuration Language) - All Terraform configuration (`.tf` files throughout `bootstrap/`, `envs/`, `modules/`)
- Makefile (GNU Make) - Workflow automation via `Makefile`
## Runtime
- Terraform >= 1.11.0 (required_version constraint in `envs/prod/versions.tf` and `bootstrap/versions.tf`)
- Native S3 state locking via `use_lockfile = true` (Terraform 1.11+ feature, eliminates DynamoDB dependency)
- None (Terraform providers are resolved via the Terraform provider registry at `registry.terraform.io`)
- Lockfile: `.terraform.lock.hcl` (generated on `terraform init`, gitignored per `/.gitignore`)
## Frameworks
- Terraform >= 1.11.0 - Infrastructure-as-code orchestration
- GNU Make - Workflow wrapper (`Makefile`); targets: `bootstrap`, `init`, `plan`, `apply`, `destroy`, `fmt`, `validate`, `clean`
- Not applicable — no automated test framework detected. Validation is done via `terraform validate` and `terraform plan`.
## Key Dependencies
- `hashicorp/aws` ~> 6.0 (AWS provider) - Declared in `envs/prod/versions.tf` and `bootstrap/versions.tf`. All AWS resource provisioning goes through this provider.
## Configuration
- Per-environment tfvars: copy `envs/prod/terraform.tfvars.example` → `envs/prod/terraform.tfvars` (gitignored)
- Key variables: `region` (default `eu-central-1`), `environment` (default `prod`), `project` (default `odoo-saas`), `tenant_domain` (must be set before building route53/acm/alb modules)
- AWS credentials: configured externally via `AWS_PROFILE`, `AWS_REGION`, or `aws configure` — not stored in this repo
- `bootstrap/versions.tf` — local-state bootstrap config (provider + version constraints)
- `envs/prod/versions.tf` — prod root config provider + version constraints
- `envs/prod/backend.tf` — S3 remote backend declaration
- `envs/prod/providers.tf` — AWS provider config with default tags
## Platform Requirements
- Terraform >= 1.11.0 installed locally
- AWS credentials configured (admin/bootstrap privileges for first run)
- GNU Make (optional, wraps common commands)
- Deployment target: AWS (`eu-central-1` default region)
- State backend: S3 bucket `odoo-saas-tfstate` (created by `bootstrap/`)
- No CI/CD pipeline defined in this repo (manual `make apply` workflow)
## Project Identity
- Project name: `odoo-saas`
- Platform: SaaS multi-tenant Odoo platform on AWS
- Resource naming convention: `{project}-{environment}` prefix, e.g. `odoo-saas-prod`
- All resources tagged: `Project=odoo-saas`, `Environment=<env>`, `ManagedBy=terraform`, `Repo=platform-terraform`
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- `snake_case` throughout — e.g., `name_prefix`, `state_bucket_name`, `noncurrent_version_expiration_days`, `tenant_domain`
- Descriptive names that reflect the resource or setting, not abbreviated
- `snake_case`, named to reflect the resource attribute exposed — e.g., `state_bucket_name`, `state_bucket_arn`, `cluster_arn`, `listener_arn`, `hosted_zone_id`
- Root env outputs include a cross-reference note in the description indicating the downstream consumer (see `envs/prod/outputs.tf`)
- `snake_case` — e.g., `name_prefix`
- Defined at the top of `main.tf`, not spread across files
- Resource label matches the logical role, not the resource type — e.g., `aws_s3_bucket.tfstate` (label is `tfstate`, not `bucket`)
- Supporting resources for the same logical object share the same label — e.g., `aws_s3_bucket.tfstate`, `aws_s3_bucket_versioning.tfstate`, `aws_s3_bucket_server_side_encryption_configuration.tfstate`, `aws_s3_bucket_public_access_block.tfstate`
- See `bootstrap/main.tf` for the canonical example of this pattern
- `snake_case` — e.g., `module "networking"`, `module "rds_tenant"`, `module "rds_proxy"`, `module "rds_control_plane"`
- Multi-word module names with hyphens in their directory names (`rds-control-plane`) are called with underscores (`rds_control_plane`)
- All `.tf` files use lowercase, no hyphens in filenames
- Standard file set per root/module: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (root configs also add `backend.tf`, `providers.tf`)
- Module directories use hyphens — e.g., `rds-control-plane/`, `rds-tenant/`
- Applied exclusively via the provider-level `default_tags` block — no per-resource `tags = {}` blocks
- Tag key names use PascalCase: `Project`, `Environment`, `ManagedBy`, `Repo`, `Component`
- Tag values are string literals or variable references, not interpolated expressions
- `ManagedBy = "terraform"` is required on every provider block
- See `bootstrap/versions.tf` and `envs/prod/providers.tf` for the two provider definitions
## Code Style
- `terraform fmt -recursive` (run via `make fmt`) — this is the canonical formatter, no additional config file
- Attribute alignment uses spaces to align `=` signs within a block (standard `terraform fmt` output)
- No `.tflint.hcl` or other linter config detected in the repo
- No pre-commit hooks detected
- Validation is performed manually via `make validate` (`terraform validate`)
## File Organization Within a Config
- `backend.tf` — backend block only; no resources
- `providers.tf` — provider block with `default_tags`; no resources
- `versions.tf` — `terraform {}` block with `required_version` and `required_providers`
- `variables.tf` — all input variables
- `outputs.tf` — all root-level outputs (commented out until their module lands)
- `main.tf` — `locals` block + module calls (commented out until implemented)
- `variables.tf` — all input variables
- `outputs.tf` — all outputs (commented out / empty until implemented)
- `main.tf` — all resources and data sources
## Description Conventions
- End with a period
- State what the variable/output IS or does, not how to use it
- Example: `"Prefix for resource names, e.g. \"odoo-saas-prod\"."`
- Use `<<-EOT` heredoc syntax
- Used when context or usage guidance requires more than one sentence
- Example: `bootstrap/variables.tf` `state_bucket_name` and `envs/prod/variables.tf` `tenant_domain`
- Include the downstream consumer mapping: `"<What it is> -> provisioner \`<setting_name>\`."`
- See the commented-out outputs in `envs/prod/outputs.tf` for the pattern
## Variable Defaults
- Provide defaults for variables that have a sensible project-wide value (region, project, environment)
- Leave no default (or default to `""`) for variables that MUST be set per-deployment (e.g., `tenant_domain`)
- Inline comment `# TODO: set in terraform.tfvars before building <module>` marks required-but-empty defaults
## Module Interface Pattern
## Comments
#
#
#
- Every non-obvious resource gets a single-line comment above it explaining WHY, not WHAT
- See `bootstrap/main.tf` — comments explain intent (e.g., "State is the source of truth... guard against accidental `terraform destroy`")
- Inline comments on individual attributes are used sparingly and only to explain non-obvious values
- Format: `# TODO: <imperative action>`
- Include inline on the relevant attribute or at the top of stub `main.tf` files
## Error Handling / Validation
- No `validation {}` blocks present in any variable as of this analysis
- No `precondition` / `postcondition` lifecycle blocks
- No `sensitive = true` annotations on outputs
- Input protection relies on type constraints (`string`, `number`) and the absence of defaults for required values
## State and Lifecycle
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
```text
```
## Component Responsibilities
| Component | Responsibility | File |
|-----------|----------------|------|
| bootstrap | Creates the S3 state bucket used by all other configs. Local state. Run once. | `bootstrap/main.tf` |
| envs/prod | Root config; declares the name_prefix local, invokes modules in build order | `envs/prod/main.tf` |
| envs/prod outputs | Re-exports module outputs as provisioner adapter settings | `envs/prod/outputs.tf` |
| modules/networking | VPC, public subnet (no NAT gateway), security groups | `modules/networking/main.tf` |
| modules/ecr | ECR pull-through cache for odoo-core image sourced from GHCR | `modules/ecr/main.tf` |
| modules/ecs | Shared ECS/Fargate cluster for all tenant tasks | `modules/ecs/main.tf` |
| modules/rds-tenant | Shared Single-AZ PostgreSQL; one database per tenant | `modules/rds-tenant/main.tf` |
| modules/rds-proxy | RDS Proxy fronting rds-tenant; activated at ~30 active tenants | `modules/rds-proxy/main.tf` |
| modules/rds-control-plane | Separate Multi-AZ PostgreSQL for control-plane (provisioner) data only | `modules/rds-control-plane/main.tf` |
| modules/efs | Shared EFS filesystem; per-tenant access points created by the provisioner adapter | `modules/efs/main.tf` |
| modules/alb | Shared ALB with host-based routing; idle timeout >60s for Odoo longpoll | `modules/alb/main.tf` |
| modules/acm | Wildcard ACM certificate for `*.{tenant_domain}` | `modules/acm/main.tf` |
| modules/route53 | Hosted zone for the tenant domain; per-tenant DNS records added by adapter | `modules/route53/main.tf` |
| modules/ssm | SSM Parameter Store SecureStrings: HMAC salt, RDS master credentials, tokens | `modules/ssm/main.tf` |
## Pattern Overview
- `bootstrap/` is a prerequisite one-shot layer that owns only the S3 state bucket. It is never called by other Terraform configs; it runs in isolation with local state.
- `envs/prod/` is the single root config for production. It composes shared infrastructure by calling all `modules/*` in a prescribed build order (see `envs/prod/main.tf` comments referencing SEED-001).
- All modules receive `name_prefix` (e.g. `"odoo-saas-prod"`) as their sole required variable, derived from `local.name_prefix = "${var.project}-${var.environment}"` in `envs/prod/main.tf`.
- Inter-module data flow is through explicit module output references (e.g. `module.networking.private_subnet_ids` → `module.rds_tenant.subnet_ids`, `module.acm.cert_arn` → `module.alb.acm_cert_arn`).
- `envs/prod/outputs.tf` is the contract between Terraform and the provisioner: every output maps 1:1 to an `AwsDeploymentAdapter` setting in `provisioner/src/provisioning_worker/settings.py`.
- All modules are stubs at scaffold stage; all resource blocks and outputs are commented out pending implementation.
## Layers
- Purpose: Provision the prerequisite remote state backend. Run once manually before anything else.
- Location: `bootstrap/`
- Contains: S3 bucket with versioning, AES-256 encryption, public access block, lifecycle rule (90-day noncurrent expiry)
- Depends on: Nothing (local state)
- Used by: `envs/prod/backend.tf` (references bucket name as the S3 backend target)
- Purpose: Wire all shared modules together into a complete environment baseline
- Location: `envs/prod/`
- Contains: `backend.tf`, `providers.tf`, `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`
- Depends on: All modules under `modules/`
- Used by: The provisioner `AwsDeploymentAdapter` (consumes outputs as runtime settings)
- Purpose: Encapsulate each AWS service domain as an independently testable unit
- Location: `modules/*/`
- Contains: `main.tf`, `variables.tf`, `outputs.tf` per module
- Depends on: Receives inputs via variables; outputs consumed by `envs/prod`
- Used by: `envs/prod/main.tf` only (no cross-module dependencies; all wiring is in the root)
## Data Flow
### Bootstrap → Remote State
### Module Composition Data Flow (envs/prod)
### Terraform Outputs → Provisioner Adapter
| Terraform output | Module source | Provisioner setting |
|-----------------|--------------|---------------------|
| `ecs_cluster_arn` | `module.ecs.cluster_arn` | `aws_ecs_cluster` |
| `private_subnet_ids` | `module.networking.private_subnet_ids` | `aws_subnets` |
| `task_security_group_id` | `module.networking.task_security_group_id` | `aws_security_groups` |
| `alb_listener_arn` | `module.alb.listener_arn` | `aws_alb_listener_arn` |
| `tenant_rds_endpoint` | `module.rds_tenant.endpoint` | `aws_shared_rds_endpoint` |
| `rds_proxy_endpoint` | `module.rds_proxy.endpoint` | `aws_rds_proxy_endpoint` |
| `efs_id` | `module.efs.efs_id` | `aws_efs_id` |
| `hosted_zone_id` | `module.route53.hosted_zone_id` | `aws_hosted_zone_id` |
| `acm_cert_arn` | `module.acm.cert_arn` | `aws_acm_cert_arn` |
| `ecr_image_uri` | `module.ecr.image_uri` | `aws_ecr_image` |
- Bootstrap: local state at `bootstrap/terraform.tfstate` (committed to git — small, non-secret)
- All envs: remote S3 state with native S3 file locking; no DynamoDB
## Key Abstractions
- Purpose: Single string (`"${project}-${environment}"` = `"odoo-saas-prod"`) threaded as the sole required input to every module, ensuring consistent resource naming and tagging
- Examples: used in every `modules/*/variables.tf`
- Pattern: constructed in `locals` block in `envs/prod/main.tf`, never hardcoded in modules
- Purpose: Placeholder modules with `main.tf`/`variables.tf`/`outputs.tf` files present but all resource blocks commented out, so `terraform plan` succeeds with zero resources during scaffold phase
- Examples: all 10 modules under `modules/`
- Pattern: header comment declares purpose + SEED-001 note + STATUS + TODO
- Purpose: `envs/prod/outputs.tf` is a typed interface between Terraform state and the provisioner service
- Examples: `envs/prod/outputs.tf`
- Pattern: output descriptions explicitly name the provisioner setting they feed (`-> provisioner aws_ecs_cluster`)
## Entry Points
- Location: `bootstrap/main.tf`
- Triggers: `make bootstrap` or `cd bootstrap && terraform init && terraform apply`
- Responsibilities: Creates versioned, encrypted S3 bucket for all remote state
- Location: `envs/prod/main.tf`
- Triggers: `make plan` / `make apply` (or `cd envs/prod && terraform plan/apply`)
- Responsibilities: Instantiates all shared infrastructure modules for production
## Architectural Constraints
- **No NAT gateway:** The networking module uses a public subnet only. Tenant ECS tasks must be in public subnets or use VPC endpoints. Explicitly chosen to reduce cost.
- **Tenant/control-plane database isolation:** `rds-tenant` and `rds-control-plane` are separate RDS instances. Mixing tenant and platform data in a single instance is explicitly forbidden (see `modules/rds-control-plane/main.tf` comment).
- **ALB idle timeout:** Must be set >60s (Odoo longpoll is ~50s). Set `healthCheckGracePeriod >= 240s` for first-boot init.
- **RDS Proxy activation threshold:** `rds-proxy` is designed to be activated at ~30 active tenants. Odoo bus LISTEN/NOTIFY must be validated through the proxy (connection pinning risk).
- **EFS mount path:** Mounted at `/var/lib/odoo` per task. Per-tenant access points created by the provisioner adapter at provision time, not by Terraform.
- **ECR pull-through cache:** Only pulls from GHCR to avoid rate limits and cold-pull risk for the ~1-2 GB `odoo-core` image.
- **SSM over Secrets Manager:** SSM Parameter Store SecureStrings are used for all secrets (HMAC salt, RDS master creds) — ~16-20x cheaper than Secrets Manager because HMAC passwords are reproducible.
- **State locking:** Requires Terraform >= 1.11 for `use_lockfile = true` (native S3 locking). No DynamoDB.
- **Global state:** No module-level singletons. All wiring is explicit in `envs/prod/main.tf`.
- **Circular imports:** Not possible — modules have no dependencies on each other. All cross-module references flow through the `envs/prod` root.
## Anti-Patterns
### Calling modules from modules
### Hardcoding resource name strings in modules
### Storing secrets in Terraform outputs or state as plaintext
## Error Handling
- `lifecycle { prevent_destroy = true }` on the S3 state bucket (`bootstrap/main.tf`) prevents accidental destruction
- S3 bucket versioning allows recovery of corrupted state files
- Incomplete multipart upload cleanup via lifecycle rule (7-day abort)
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
