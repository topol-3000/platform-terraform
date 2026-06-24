# Phase 3: Databases and Secrets - Pattern Map

**Mapped:** 2026-06-23
**Files analyzed:** 12 (4 module trios + 4 env/prod files)
**Analogs found:** 12 / 12

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `modules/ssm/main.tf` | module/service | CRUD | `modules/ecr/main.tf` | role-match (resource body + header comment structure) |
| `modules/ssm/variables.tf` | config | — | `modules/ecs/variables.tf` | exact (name_prefix-only variables.tf) |
| `modules/ssm/outputs.tf` | config | — | `modules/ecs/outputs.tf` | exact (single-concern typed output) |
| `modules/rds-tenant/main.tf` | module/service | CRUD | `modules/networking/main.tf` | exact (SG-reference ingress pattern; resource body + WHY-comments) |
| `modules/rds-tenant/variables.tf` | config | — | `modules/networking/variables.tf` | exact (name_prefix + typed list variable) |
| `modules/rds-tenant/outputs.tf` | config | — | `modules/networking/outputs.tf` | exact (typed outputs, descriptive sentences) |
| `modules/rds-proxy/main.tf` | module/service | CRUD | `modules/networking/main.tf` | role-match (SG-reference ingress; count-gate pattern is unique) |
| `modules/rds-proxy/variables.tf` | config | — | `modules/networking/variables.tf` | exact (same variable structure) |
| `modules/rds-proxy/outputs.tf` | config | — | `modules/ecs/outputs.tf` + try() guard | role-match (single output, but requires try() guard) |
| `modules/rds-control-plane/main.tf` | module/service | CRUD | `modules/rds-tenant/main.tf` (once written) + `bootstrap/main.tf` (lifecycle pattern) | exact (identical structure; multi_az=true is the only difference) |
| `modules/rds-control-plane/variables.tf` | config | — | `modules/networking/variables.tf` | exact |
| `modules/rds-control-plane/outputs.tf` | config | — | `modules/ecs/outputs.tf` | exact |
| `envs/prod/main.tf` | config | — | `envs/prod/main.tf` (self — uncomment stubs) | exact (stubs already present lines 35-77) |
| `envs/prod/outputs.tf` | config | — | `envs/prod/outputs.tf` (self — uncomment stubs) | exact (stubs already present lines 36-44) |
| `envs/prod/variables.tf` | config | — | `envs/prod/variables.tf` (self — add new vars) | exact (established variable block pattern) |
| `envs/prod/versions.tf` | config | — | `envs/prod/versions.tf` (self — add random provider) | exact |

---

## Pattern Assignments

### `modules/ssm/main.tf` (module, CRUD)

**Analog:** `modules/ecr/main.tf`

**Header comment pattern** (`modules/ecr/main.tf` lines 1-8, `modules/rds-tenant/main.tf` lines 1-10):
```hcl
# Module: ssm
# Purpose: SSM Parameter Store SecureStrings (HMAC salt, RDS master creds)
#
# SEED-001 note: Parameter Store NOT Secrets Manager (~16-20x cheaper; HMAC passwords are reproducible).
#          RDS Proxy is the sole Secrets Manager exception — materialises only when enable_rds_proxy = true.
```

**Resource naming convention** (`modules/ecr/main.tf` line 12, `modules/ecs/main.tf` line 10):
```hcl
# All resource names: "${var.name_prefix}-<thing>"
resource "aws_ecr_repository" "odoo_core" {
  name = "${var.name_prefix}-odoo-core"
  ...
}
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"
  ...
}
```

**Tags convention** (`modules/ecr/main.tf` line 31, `modules/ecs/main.tf` line 21 — only `Name` tag per resource):
```hcl
  tags = { Name = "${var.name_prefix}-odoo-core" }
```

**Core pattern — random_password → aws_ssm_parameter chain** (from RESEARCH.md Pattern 1; no existing analog in codebase, use research verbatim):
```hcl
resource "random_password" "tenant_rds" {
  length           = 32
  special          = true
  # Exclude / @ " and spaces — characters that can break Postgres connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "tenant_rds_password" {
  name  = "/${var.name_prefix}/rds/tenant/master-password"
  type  = "SecureString"
  value = random_password.tenant_rds.result
  # key_id omitted → uses default alias/aws/ssm (AWS-managed key, D-09)

  lifecycle {
    ignore_changes = [value] # Allow out-of-band rotation without Terraform drift (D-02)
  }

  tags = { Name = "${var.name_prefix}-rds-tenant-password" }
}
```

**WHY-comment style** (`modules/ecr/main.tf` lines 33-35, `bootstrap/main.tf` lines 7-9):
```hcl
  # State is the source of truth for live infrastructure — guard against an
  # accidental `terraform destroy` of the bootstrap itself.
  lifecycle {
    prevent_destroy = true
  }
```
Apply same "why not what" style above each resource block in `modules/ssm/main.tf`.

**SSM module boundary:** Generate all `random_password` resources inside `modules/ssm`. Export raw `result` values as `sensitive = true` outputs to the root (for RDS password wiring). Export only parameter names/ARNs in non-sensitive outputs (for the provisioner contract). Never export `.value` on an `aws_ssm_parameter`.

---

### `modules/ssm/variables.tf` (config)

**Analog:** `modules/ecs/variables.tf` (lines 1-4 — canonical name_prefix-only stub)

**Pattern** (exact copy of structure):
```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}
```
`modules/ssm` has no other required inputs — `random_password` generates internally; no subnet or SG inputs needed.

---

### `modules/ssm/outputs.tf` (config)

**Analog:** `modules/ecs/outputs.tf` (line 1-4) and `modules/networking/outputs.tf` (lines 1-19)

**Pattern — output descriptive sentence, typed value** (`modules/ecs/outputs.tf` lines 1-4):
```hcl
output "cluster_arn" {
  description = "Shared ECS cluster ARN for the tenant Fargate fleet."
  value       = aws_ecs_cluster.main.arn
}
```

**SSM-specific pattern — sensitive outputs for password wiring, non-sensitive for provisioner contract:**
```hcl
# Non-secret reference outputs (names/ARNs only — for provisioner contract).
output "tenant_rds_password_name" {
  description = "SSM parameter name for the tenant RDS master password."
  value       = aws_ssm_parameter.tenant_rds_password.name
}

output "tenant_rds_password_arn" {
  description = "SSM parameter ARN for the tenant RDS master password."
  value       = aws_ssm_parameter.tenant_rds_password.arn
}

# Sensitive pass-through outputs — raw random_password.result for RDS wiring only.
# These values are in encrypted state but MUST NOT appear in envs/prod/outputs.tf.
output "tenant_rds_password" {
  description = "Tenant RDS master password (sensitive). Passed to rds-tenant module only."
  value       = random_password.tenant_rds.result
  sensitive   = true
}
```

**Critical rule:** Never output `aws_ssm_parameter.*.value` — that exposes the secret in state diff. Always output `random_password.*.result` with `sensitive = true` for the inter-module pass-through.

---

### `modules/rds-tenant/main.tf` (module, CRUD)

**Analog:** `modules/networking/main.tf` (lines 86-108 — the SG-reference ingress template)

**Header comment** (same format as `modules/networking/main.tf` lines 1-5):
```hcl
# Module: rds-tenant
# Purpose: Shared Single-AZ PostgreSQL instance, DB subnet group, and RDS security group.
#          The provisioner adapter creates per-tenant databases and roles at runtime; this
#          module owns only the shared instance and network resources.
#
# SEED-001 note: Single-AZ at MVP (cost). Size on max_connections (~5-20 conns/tenant).
#          multi_az = false here; see rds-control-plane for the Multi-AZ control-plane instance.
```

**RDS Security Group — SG-reference ingress** (`modules/networking/main.tf` lines 86-108 — THE template):
```hcl
# Task security group — only the ALB may reach Odoo on 8069 (SG reference, not CIDR — D-09).
# Tasks are on public subnets; this SG is the sole guard against direct internet exposure.
resource "aws_security_group" "task" {
  name_prefix = "${var.name_prefix}-task-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Odoo port from ALB only"
    from_port       = 8069
    to_port         = 8069
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # NOT a CIDR — prevents direct internet access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-task-sg" }
}
```

**Adapt for RDS tenant SG** — replace `alb.id` reference with `var.task_security_group_id`, port 8069 with 5432, name suffix with `-rds-tenant-`:
```hcl
# RDS security group — only ECS tasks may reach PostgreSQL on 5432 (SG reference, not CIDR).
resource "aws_security_group" "rds_tenant" {
  name_prefix = "${var.name_prefix}-rds-tenant-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from task SG only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.task_security_group_id] # NOT a CIDR — SG reference per Phase 1 pattern
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-rds-tenant-sg" }
}
```

**`lifecycle { prevent_destroy }` and WHY-comment** — deletion_protection analog from `bootstrap/main.tf` lines 7-13:
```hcl
  # State is the source of truth for live infrastructure — guard against an
  # accidental `terraform destroy` of the bootstrap itself.
  lifecycle {
    prevent_destroy = true
  }
```
Apply equivalent reasoning in `aws_db_instance.tenant` WHY-comment:
```hcl
  # Tenant data lives here — deletion_protection + final snapshot guard against
  # an accidental destroy of the shared instance (mirroring the bootstrap S3 ethos).
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-tenant-rds-final"

  lifecycle {
    ignore_changes = [password] # D-02: allow out-of-band rotation without Terraform drift
  }
```

**No per-resource tags beyond Name** (`modules/ecs/main.tf` line 21, `modules/ecr/main.tf` line 31):
```hcl
  tags = { Name = "${var.name_prefix}-tenant-rds" }
```
Provider `default_tags` supplies Project/Environment/ManagedBy/Repo automatically.

---

### `modules/rds-tenant/variables.tf` (config)

**Analog:** `modules/networking/variables.tf` (lines 1-24 — name_prefix + typed variables with defaults)

**Pattern — name_prefix (required, no default):**
```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}
```

**Pattern — list variable with type annotation** (`modules/networking/variables.tf` lines 17-24):
```hcl
variable "azs" {
  description = "Availability zones to place one public subnet in each."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  ...
}
```
Adapt for `subnet_ids`:
```hcl
variable "subnet_ids" {
  description = "Subnet IDs for the RDS DB subnet group. Requires >=2 subnets in different AZs."
  type        = list(string)
}
```

**New variables to pre-declare** (D-11 — must exist before the module call is uncommented):
```hcl
variable "vpc_id" {
  description = "VPC id for the RDS security group."
  type        = string
}

variable "task_security_group_id" {
  description = "Security group id for tenant ECS tasks. RDS SG allows 5432 ingress from this SG only."
  type        = string
}

variable "master_password" {
  description = "RDS master password (sensitive). Sourced from modules/ssm random_password output."
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS instance class for the tenant PostgreSQL instance."
  type        = string
  default     = "db.t4g.small"
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling in GiB."
  type        = number
  default     = 100
}
```

---

### `modules/rds-tenant/outputs.tf` (config)

**Analog:** `modules/networking/outputs.tf` (lines 1-19) and `modules/ecs/outputs.tf` (lines 1-4)

**Pattern** (`modules/networking/outputs.tf` lines 1-19):
```hcl
output "vpc_id" {
  description = "VPC id for downstream modules (rds, ecs, alb)."
  value       = aws_vpc.main.id
}

output "task_security_group_id" {
  description = "Security group id for tenant ECS tasks."
  value       = aws_security_group.task.id
}
```

**Adapt for rds-tenant** — one output per exported attribute; descriptions end with a period:
```hcl
output "endpoint" {
  description = "Shared tenant RDS endpoint -> provisioner `aws_shared_rds_endpoint`."
  value       = aws_db_instance.tenant.endpoint
}

output "identifier" {
  description = "RDS instance identifier. Passed to rds-proxy as db_instance_identifier."
  value       = aws_db_instance.tenant.identifier
}

output "security_group_id" {
  description = "RDS tenant security group id. Passed to rds-proxy for proxy SG ingress wiring."
  value       = aws_security_group.rds_tenant.id
}

output "db_resource_id" {
  description = "RDS resource id (DbiResourceId). Used for IAM authentication if added later."
  value       = aws_db_instance.tenant.resource_id
}
```

Note the `-> provisioner \`aws_shared_rds_endpoint\`` description convention — mirrors `envs/prod/outputs.tf` lines 7, 37.

---

### `modules/rds-proxy/main.tf` (module, CRUD)

**Analog:** `modules/networking/main.tf` (SG pattern) + count-gate pattern from RESEARCH.md Pattern 5 (no existing codebase analog — use research)

**Header comment:**
```hcl
# Module: rds-proxy
# Purpose: RDS Proxy fronting the shared tenant RDS instance.
#
# SEED-001 note: Activate by ~30 active tenants. Validate Odoo bus LISTEN/NOTIFY through
#          the proxy (connection-pinning risk) before relying on it in production.
#          All resources gated behind var.enable_rds_proxy (default false).
#          The Secrets Manager secret here is the sole exception to the SSM-only rule.
```

**Count-gate pattern** — every resource in this module uses the same gate (no existing codebase analog):
```hcl
resource "aws_secretsmanager_secret" "proxy_auth" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${var.name_prefix}-rds-proxy-auth"
  # ... description, tags
}
```

**SG pattern within the proxy module** — copy from `modules/networking/main.tf` lines 86-108 with `var.task_security_group_id` as the ingress source, same as rds-tenant:
```hcl
resource "aws_security_group" "proxy" {
  count       = var.enable_rds_proxy ? 1 : 0
  name_prefix = "${var.name_prefix}-rds-proxy-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from task SG to proxy"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.task_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-rds-proxy-sg" }
}
```

---

### `modules/rds-proxy/variables.tf` (config)

**Analog:** `modules/networking/variables.tf` (same structure)

**New variables to pre-declare** (D-11):
```hcl
variable "name_prefix" { ... }

variable "enable_rds_proxy" {
  description = "Enable the RDS Proxy. Set true at ~30 active tenants."
  type        = bool
  default     = false
}

variable "db_instance_identifier" {
  description = "RDS instance identifier to attach the proxy to. Sourced from module.rds_tenant.identifier."
  type        = string
  default     = ""  # TODO: set when enable_rds_proxy = true
}

variable "subnet_ids" {
  description = "Subnet IDs for the RDS Proxy ENIs."
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC id for the proxy security group."
  type        = string
  default     = ""
}

variable "task_security_group_id" {
  description = "Security group id for ECS tasks. Proxy SG allows 5432 ingress from this SG only."
  type        = string
  default     = ""
}

variable "master_username" {
  description = "RDS master username. Stored in the Secrets Manager secret for proxy auth."
  type        = string
  default     = "odoo_master"
}

variable "master_password" {
  description = "RDS master password (sensitive). Stored in the Secrets Manager secret for proxy auth."
  type        = string
  sensitive   = true
  default     = ""
}
```

---

### `modules/rds-proxy/outputs.tf` (config)

**Analog:** `modules/ecs/outputs.tf` (lines 1-4) + `try()` guard (from RESEARCH.md D-06)

**Pattern — try() guard is mandatory when count may be 0:**
```hcl
output "endpoint" {
  description = "RDS Proxy endpoint -> provisioner `aws_rds_proxy_endpoint`. Null when enable_rds_proxy is false."
  value       = try(aws_db_proxy.this[0].endpoint, null)
}
```

`try()` is the canonical form. Do NOT use `length(aws_db_proxy.this) > 0 ? aws_db_proxy.this[0].endpoint : null` — `try()` is idiomatic and does not evaluate the index expression at all when the list is empty (RESEARCH.md "Don't Hand-Roll" table).

---

### `modules/rds-control-plane/main.tf` (module, CRUD)

**Analog:** Same pattern as `modules/rds-tenant/main.tf` — structurally identical, with these differences:
- `multi_az = true`
- All resource labels use `cp` or `control_plane` suffix instead of `tenant`
- `identifier = "${var.name_prefix}-cp-rds"`
- `final_snapshot_identifier = "${var.name_prefix}-cp-rds-final"`
- `db_name = "provisioner"` (platform data, not tenant data)

**lifecycle / deletion_protection pattern** (`bootstrap/main.tf` lines 7-13 — WHY-comment analog):
```hcl
  # Control-plane data must never be accidentally destroyed — this is the provisioner's
  # operational database. deletion_protection + final snapshot mirror the bootstrap S3 ethos.
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-cp-rds-final"

  lifecycle {
    ignore_changes = [password] # D-02: allow out-of-band rotation without Terraform drift
  }
```

**SEED-001 isolation note** (mirrors existing stub header `modules/rds-control-plane/main.tf` line 3):
```hcl
# SEED-001 note: MUST be separate from the tenant RDS. Never mix tenant + platform data.
#          multi_az = true (Multi-AZ for 99.9% SLA on provisioner operational data).
```

---

### `modules/rds-control-plane/variables.tf` and `outputs.tf` (config)

**Exact same structure as `modules/rds-tenant/variables.tf` and `outputs.tf`** — same set of variables, same output pattern. The only output needed by the provisioner contract is `endpoint`. Add `security_group_id` for completeness if future modules need it.

---

### `envs/prod/main.tf` — uncomment and wire stubs (config)

**Analog:** Self — the stubs are already written at lines 35-77. The pattern for an already-wired module call is established at lines 15-32 (networking, ecr, ecs).

**Existing wired module call pattern** (`envs/prod/main.tf` lines 15-20):
```hcl
module "networking" {
  source      = "../../modules/networking"
  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
}
```

**Stubs to uncomment and fill** (`envs/prod/main.tf` lines 35-77) — the stub interface already shows:
```hcl
# module "rds_tenant" {
#   source      = "../../modules/rds-tenant"
#   name_prefix = local.name_prefix
#   subnet_ids  = module.networking.private_subnet_ids
# }
```
Expand to full wiring by adding the new variables declared in D-11:
```hcl
module "rds_tenant" {
  source                 = "../../modules/rds-tenant"
  name_prefix            = local.name_prefix
  subnet_ids             = module.networking.private_subnet_ids
  vpc_id                 = module.networking.vpc_id
  task_security_group_id = module.networking.task_security_group_id
  master_password        = module.ssm.tenant_rds_password
}
```

**Module label convention — underscore, not hyphen** (`envs/prod/main.tf` line 35, RESEARCH.md Pitfall 6):
```hcl
module "rds_tenant"        # correct
# module "rds-tenant"      # WRONG — reference module.rds_tenant.* would not resolve
```

**Section comment style** (`envs/prod/main.tf` lines 14, 22, 28):
```hcl
# --- 5. Databases -------------------------------------------------------------
```

---

### `envs/prod/outputs.tf` — uncomment stubs and add control-plane output (config)

**Analog:** Self — pattern already established at lines 6-24 (live outputs) and lines 36-44 (commented stubs).

**Existing live output pattern** (`envs/prod/outputs.tf` lines 6-9):
```hcl
output "ecs_cluster_arn" {
  description = "Shared ECS cluster ARN -> provisioner `aws_ecs_cluster`."
  value       = module.ecs.cluster_arn
}
```

**Stubs to uncomment** (`envs/prod/outputs.tf` lines 36-44):
```hcl
# output "tenant_rds_endpoint" {
#   description = "Shared tenant RDS endpoint -> provisioner `aws_shared_rds_endpoint`."
#   value       = module.rds_tenant.endpoint
# }
#
# output "rds_proxy_endpoint" {
#   description = "RDS Proxy endpoint -> provisioner `aws_rds_proxy_endpoint`."
#   value       = module.rds_proxy.endpoint
# }
```

**New output to add** (no stub exists — use same description convention with `-> provisioner` reference):
```hcl
output "control_plane_rds_endpoint" {
  description = "Control-plane RDS endpoint -> provisioner `aws_control_plane_rds_endpoint`."
  value       = module.rds_control_plane.endpoint
}
```

**SSM outputs — names/ARNs only, never values** (description convention from lines 11-13):
```hcl
output "tenant_rds_password_name" {
  description = "SSM parameter name for the tenant RDS master password -> provisioner secret lookup."
  value       = module.ssm.tenant_rds_password_name
}
```
Do NOT add an output that references `module.ssm.tenant_rds_password` (the sensitive raw value) — that must never appear in the provisioner-facing output contract.

---

### `envs/prod/variables.tf` — add new variables (config)

**Analog:** `envs/prod/variables.tf` (self — lines 1-47, established variable block pattern)

**Existing pattern — variable with sensible default** (`envs/prod/variables.tf` lines 1-5):
```hcl
variable "region" {
  description = "AWS region for the prod baseline. Must match the state bucket region."
  type        = string
  default     = "us-east-1"
}
```

**New variable to add — enable_rds_proxy (default false, prod-safe):**
```hcl
variable "enable_rds_proxy" {
  description = "Enable the RDS Proxy module. Set true at ~30 active tenants."
  type        = bool
  default     = false
}
```

**New sizing variables (overridable via tfvars; provide prod-sensible defaults):**
```hcl
variable "rds_instance_class" {
  description = "RDS instance class for both tenant and control-plane instances."
  type        = string
  default     = "db.t4g.small"
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version for all RDS instances."
  type        = string
  default     = "16"
}

variable "rds_allocated_storage" {
  description = "Initial allocated storage in GiB for each RDS instance."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling in GiB."
  type        = number
  default     = 100
}
```

---

### `envs/prod/versions.tf` — add hashicorp/random (config)

**Analog:** Self (`envs/prod/versions.tf` lines 1-10 — existing `required_providers` block)

**Existing pattern** (lines 1-10):
```hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

**Add random provider block inside `required_providers`:**
```hcl
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
```

Final result:
```hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```

---

## Shared Patterns

### Pattern A: Resource Naming — `"${var.name_prefix}-<thing>"`

**Source:** `modules/networking/main.tf` line 13, `modules/ecs/main.tf` line 10, `modules/ecr/main.tf` line 12.
**Apply to:** Every `name`, `name_prefix`, or `identifier` attribute in all four modules.

```hcl
name        = "${var.name_prefix}-tenant-rds"         # aws_db_instance
name_prefix = "${var.name_prefix}-rds-tenant-"        # aws_security_group (trailing dash)
name        = "${var.name_prefix}-tenant-rds"         # aws_db_subnet_group
identifier  = "${var.name_prefix}-tenant-rds"         # aws_db_instance identifier
name_prefix = "${var.name_prefix}-tenant-pg16-"       # aws_db_parameter_group (trailing dash)
```

### Pattern B: Tags — Only `Name` Per Resource

**Source:** `modules/networking/main.tf` lines 13, 25, 43, 84, 107. `modules/ecs/main.tf` line 21. `modules/ecr/main.tf` line 31.
**Apply to:** Every resource in all four new modules.

```hcl
  tags = { Name = "${var.name_prefix}-rds-tenant-sg" }
```

Provider `default_tags` in `envs/prod/providers.tf` supplies `Project`, `Environment`, `ManagedBy`, `Repo` automatically. Do not repeat those keys per-resource.

### Pattern C: WHY-Comments, Not WHAT-Comments

**Source:** `modules/networking/main.tf` lines 7, 16, 28, 35, 47, 55-57, 86-88. `bootstrap/main.tf` lines 7-9, 15-16, 24-25.
**Apply to:** Every non-obvious resource in all four modules.

```hcl
# bootstrap/main.tf lines 7-9
# State is the source of truth for live infrastructure — guard against an
# accidental `terraform destroy` of the bootstrap itself.
```

### Pattern D: SG-Reference Ingress (Not CIDR)

**Source:** `modules/networking/main.tf` lines 86-108 — `security_groups = [aws_security_group.alb.id]`.
**Apply to:** All three RDS security groups (`rds-tenant`, `rds-control-plane`, `rds-proxy`).

```hcl
  ingress {
    description     = "PostgreSQL from task SG only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.task_security_group_id] # NOT a CIDR — SG reference per Phase 1 pattern
  }
```

Never use `cidr_blocks` for the 5432 ingress rule. The egress allow-all (`cidr_blocks = ["0.0.0.0/0"]`) is the only CIDR in the RDS SGs.

### Pattern E: Module Variable Declaration — name_prefix, typed, no extra defaults

**Source:** `modules/ecs/variables.tf` (lines 1-4), `modules/networking/variables.tf` (lines 1-24).
**Apply to:** `variables.tf` in all four new modules.

```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}
```

Required inputs (no default): `name_prefix`, `subnet_ids`, `vpc_id`, `task_security_group_id`, `master_password`.
Optional inputs with prod-sensible defaults: `instance_class`, `engine_version`, `allocated_storage`, `max_allocated_storage`.

### Pattern F: `lifecycle { ignore_changes }` for Out-of-Band Rotation

**Source:** `bootstrap/main.tf` lines 9-12 (`lifecycle { prevent_destroy = true }`) — establishes the lifecycle block convention.
**Apply to:** `aws_db_instance` in both rds-tenant and rds-control-plane; `aws_ssm_parameter` in ssm.

```hcl
  lifecycle {
    ignore_changes = [password] # D-02: allow out-of-band rotation without Terraform drift
  }

  lifecycle {
    ignore_changes = [value] # D-02: allow out-of-band SSM rotation without Terraform drift
  }
```

Also: `aws_db_parameter_group` requires `create_before_destroy = true` (different from `prevent_destroy`):
```hcl
  lifecycle {
    create_before_destroy = true # Required to avoid name conflict during replacement
  }
```

### Pattern G: Provisioner Output Contract — `-> provisioner \`setting_name\`` Description Convention

**Source:** `envs/prod/outputs.tf` lines 7, 12, 17, 37, 41 (live and commented stubs).
**Apply to:** All outputs in `envs/prod/outputs.tf` that feed the provisioner adapter.

```hcl
output "ecs_cluster_arn" {
  description = "Shared ECS cluster ARN -> provisioner `aws_ecs_cluster`."
  value       = module.ecs.cluster_arn
}
```

### Pattern H: `try()` Guard for Count-Gated Resources

**Source:** RESEARCH.md Pattern 5, "Don't Hand-Roll" table. No codebase analog yet.
**Apply to:** `modules/rds-proxy/outputs.tf` endpoint output.

```hcl
output "endpoint" {
  description = "RDS Proxy endpoint -> provisioner `aws_rds_proxy_endpoint`. Null when enable_rds_proxy is false."
  value       = try(aws_db_proxy.this[0].endpoint, null)
}
```

---

## No Analog Found

All files in Phase 3 have a codebase analog for structure and naming. The following patterns have no existing codebase instance and must be implemented from RESEARCH.md:

| Pattern | Reason No Analog Exists |
|---------|------------------------|
| `random_password` resource | `hashicorp/random` not yet used in codebase |
| `aws_ssm_parameter` SecureString | SSM module is a stub; no implemented SSM resources yet |
| `aws_db_instance` with all production attributes | RDS modules are stubs; no existing `aws_db_instance` |
| `aws_db_subnet_group` | No existing subnet group resource |
| `aws_db_parameter_group` | No existing parameter group resource |
| `aws_db_proxy` + count-gate pattern | RDS Proxy module is a stub; no count-gated resources yet |
| `aws_secretsmanager_secret` | First Secrets Manager resource in the repo |
| `aws_iam_role` + `aws_iam_role_policy` | No IAM resources in codebase yet |
| `try()` conditional output | No count-gated resource outputs yet |

For all of the above, use RESEARCH.md §Code Examples (Patterns 1–6) as the primary reference. The structural conventions (naming, tags, lifecycle, comments) copy from existing codebase analogs documented above.

---

## Metadata

**Analog search scope:** `modules/networking/`, `modules/ecs/`, `modules/ecr/`, `bootstrap/`, `envs/prod/`
**Files scanned:** 14
**Pattern extraction date:** 2026-06-23
