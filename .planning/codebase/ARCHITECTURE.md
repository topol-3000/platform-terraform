<!-- refreshed: 2026-06-19 -->
# Architecture

**Analysis Date:** 2026-06-19

## System Overview

```text
┌──────────────────────────────────────────────────────────────────┐
│                      envs/prod/                                   │
│  Root Terraform config — wires all shared modules together        │
│  `envs/prod/main.tf`                                             │
└──┬──────────┬──────────┬──────────┬──────────┬──────────┬───────┘
   │          │          │          │          │          │
   ▼          ▼          ▼          ▼          ▼          ▼
┌──────┐ ┌──────┐ ┌──────────────────────────────┐ ┌──────────────┐
│ ecr  │ │ ecs  │ │         databases             │ │  routing/TLS │
│      │ │      │ ├──────────┬────────┬───────────┤ ├────┬───┬─────┤
│`mods/│ │`mods/│ │rds-tenant│rds-    │rds-control│ │alb │   │acm  │
│ecr/` │ │ecs/` │ │`mods/    │proxy   │-plane     │ │`mods│   │`mods│
│      │ │      │ │rds-      │`mods/  │`mods/rds- │ │alb/`│   │acm/`│
│      │ │      │ │tenant/`  │rds-    │control-   │ │     │   │     │
│      │ │      │ │          │proxy/` │plane/`    │ │     │   │     │
└──────┘ └──────┘ └──────────┴────────┴───────────┘ └────┘   └─────┘

┌──────────────────┐  ┌──────────────┐  ┌──────────┐  ┌──────────┐
│   networking     │  │     efs      │  │ route53  │  │   ssm    │
│`modules/         │  │`modules/efs/`│  │`modules/ │  │`modules/ │
│ networking/`     │  │              │  │ route53/`│  │  ssm/`   │
└──────────────────┘  └──────────────┘  └──────────┘  └──────────┘

┌──────────────────────────────────────────────────────────────────┐
│                        bootstrap/                                 │
│  One-shot local-state config — creates S3 remote state bucket     │
│  `bootstrap/main.tf`                                             │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                   S3 Remote State Backend                         │
│  Bucket: odoo-saas-tfstate  Key: prod/baseline.tfstate            │
│  Native S3 locking (use_lockfile=true). No DynamoDB.              │
└──────────────────────────────────────────────────────────────────┘
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

**Overall:** Layered root-module composition with environment-scoped root configs.

**Key Characteristics:**
- `bootstrap/` is a prerequisite one-shot layer that owns only the S3 state bucket. It is never called by other Terraform configs; it runs in isolation with local state.
- `envs/prod/` is the single root config for production. It composes shared infrastructure by calling all `modules/*` in a prescribed build order (see `envs/prod/main.tf` comments referencing SEED-001).
- All modules receive `name_prefix` (e.g. `"odoo-saas-prod"`) as their sole required variable, derived from `local.name_prefix = "${var.project}-${var.environment}"` in `envs/prod/main.tf`.
- Inter-module data flow is through explicit module output references (e.g. `module.networking.private_subnet_ids` → `module.rds_tenant.subnet_ids`, `module.acm.cert_arn` → `module.alb.acm_cert_arn`).
- `envs/prod/outputs.tf` is the contract between Terraform and the provisioner: every output maps 1:1 to an `AwsDeploymentAdapter` setting in `provisioner/src/provisioning_worker/settings.py`.
- All modules are stubs at scaffold stage; all resource blocks and outputs are commented out pending implementation.

## Layers

**Bootstrap Layer:**
- Purpose: Provision the prerequisite remote state backend. Run once manually before anything else.
- Location: `bootstrap/`
- Contains: S3 bucket with versioning, AES-256 encryption, public access block, lifecycle rule (90-day noncurrent expiry)
- Depends on: Nothing (local state)
- Used by: `envs/prod/backend.tf` (references bucket name as the S3 backend target)

**Environment Root Layer:**
- Purpose: Wire all shared modules together into a complete environment baseline
- Location: `envs/prod/`
- Contains: `backend.tf`, `providers.tf`, `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`
- Depends on: All modules under `modules/`
- Used by: The provisioner `AwsDeploymentAdapter` (consumes outputs as runtime settings)

**Module Layer:**
- Purpose: Encapsulate each AWS service domain as an independently testable unit
- Location: `modules/*/`
- Contains: `main.tf`, `variables.tf`, `outputs.tf` per module
- Depends on: Receives inputs via variables; outputs consumed by `envs/prod`
- Used by: `envs/prod/main.tf` only (no cross-module dependencies; all wiring is in the root)

## Data Flow

### Bootstrap → Remote State

1. Engineer runs `make bootstrap` (`bootstrap/main.tf`)
2. Terraform creates S3 bucket `odoo-saas-tfstate` with versioning + encryption
3. `envs/prod/backend.tf` references this bucket (`key = "prod/baseline.tfstate"`)
4. All subsequent `terraform init` in `envs/prod/` use S3 native locking (`use_lockfile = true`)

### Module Composition Data Flow (envs/prod)

Planned wiring order as documented in `envs/prod/main.tf`:

1. `module "networking"` → produces VPC id, subnet ids, security group ids
2. `module "ecr"` → produces ECR image URI
3. `module "ecs"` → produces ECS cluster ARN
4. `module "rds_tenant"` (consumes `module.networking.private_subnet_ids`) → produces RDS endpoint
5. `module "rds_proxy"` → produces proxy endpoint
6. `module "rds_control_plane"` → produces control-plane RDS endpoint (isolated from tenant data)
7. `module "efs"` → produces EFS filesystem id
8. `module "acm"` (consumes `var.tenant_domain`) → produces wildcard cert ARN
9. `module "alb"` (consumes `module.acm.cert_arn`) → produces ALB listener ARN
10. `module "route53"` (consumes `var.tenant_domain`) → produces hosted zone id
11. `module "ssm"` → produces SSM parameter paths for secrets

### Terraform Outputs → Provisioner Adapter

`envs/prod/outputs.tf` re-exports module outputs to the `AwsDeploymentAdapter`:

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

**State Management:**
- Bootstrap: local state at `bootstrap/terraform.tfstate` (committed to git — small, non-secret)
- All envs: remote S3 state with native S3 file locking; no DynamoDB

## Key Abstractions

**name_prefix:**
- Purpose: Single string (`"${project}-${environment}"` = `"odoo-saas-prod"`) threaded as the sole required input to every module, ensuring consistent resource naming and tagging
- Examples: used in every `modules/*/variables.tf`
- Pattern: constructed in `locals` block in `envs/prod/main.tf`, never hardcoded in modules

**Module stub:**
- Purpose: Placeholder modules with `main.tf`/`variables.tf`/`outputs.tf` files present but all resource blocks commented out, so `terraform plan` succeeds with zero resources during scaffold phase
- Examples: all 10 modules under `modules/`
- Pattern: header comment declares purpose + SEED-001 note + STATUS + TODO

**Provisioner output contract:**
- Purpose: `envs/prod/outputs.tf` is a typed interface between Terraform state and the provisioner service
- Examples: `envs/prod/outputs.tf`
- Pattern: output descriptions explicitly name the provisioner setting they feed (`-> provisioner aws_ecs_cluster`)

## Entry Points

**Bootstrap (one-shot):**
- Location: `bootstrap/main.tf`
- Triggers: `make bootstrap` or `cd bootstrap && terraform init && terraform apply`
- Responsibilities: Creates versioned, encrypted S3 bucket for all remote state

**Prod environment:**
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

**What happens:** Terraform child modules that themselves call other modules
**Why it's wrong:** Creates hidden coupling; makes the dependency graph opaque and hard to `plan` incrementally
**Do this instead:** All module wiring must be done in the root config `envs/prod/main.tf` — pass outputs explicitly as variables

### Hardcoding resource name strings in modules

**What happens:** Resource names constructed inside a module without using `var.name_prefix`
**Why it's wrong:** Breaks the naming contract; makes resources unidentifiable by environment
**Do this instead:** All resource names must be prefixed with `var.name_prefix` (e.g. `"${var.name_prefix}-ecs-cluster"`)

### Storing secrets in Terraform outputs or state as plaintext

**What happens:** Outputting RDS passwords or HMAC salts as non-sensitive string outputs
**Why it's wrong:** Terraform state is stored in S3 and can be read by anyone with bucket access; secrets would be exposed
**Do this instead:** Store all credentials via `modules/ssm` as SecureStrings. State bucket has AES-256 SSE enabled (`bootstrap/main.tf`)

## Error Handling

**Strategy:** Terraform plan/apply errors surface as CLI output. No custom error handling in HCL.

**Patterns:**
- `lifecycle { prevent_destroy = true }` on the S3 state bucket (`bootstrap/main.tf`) prevents accidental destruction
- S3 bucket versioning allows recovery of corrupted state files
- Incomplete multipart upload cleanup via lifecycle rule (7-day abort)

## Cross-Cutting Concerns

**Tagging:** All resources receive a consistent tag set via `provider "aws" { default_tags {} }` in both `bootstrap/versions.tf` and `envs/prod/providers.tf`: `Project=odoo-saas`, `Environment`, `ManagedBy=terraform`, `Repo=platform-terraform`

**Validation:** `make validate` runs `terraform validate` in `envs/prod/`

**Formatting:** `make fmt` runs `terraform fmt -recursive` across the whole repo

---

*Architecture analysis: 2026-06-19*
