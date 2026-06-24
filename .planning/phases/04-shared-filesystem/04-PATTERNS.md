# Phase 4: Shared Filesystem - Pattern Map

**Mapped:** 2026-06-24
**Files analyzed:** 5 new/modified files
**Analogs found:** 5 / 5

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `modules/efs/main.tf` | module/service | CRUD (provision-once) | `modules/rds-tenant/main.tf` | exact (SG-ref ingress + named resource block) |
| `modules/efs/variables.tf` | config | — | `modules/rds-tenant/variables.tf` | exact (same variable shape: name_prefix, subnet_ids, vpc_id, task_sg_id) |
| `modules/efs/outputs.tf` | config | — | `modules/ecs/outputs.tf` | exact (single-value typed output) |
| `envs/prod/main.tf` | root wiring | — | same file (existing `module "rds_tenant"` block) | exact (underscore label + local.name_prefix + module.networking.* args) |
| `envs/prod/outputs.tf` | root wiring | — | same file (existing uncommented outputs) | exact (module.X.attr shape, provisioner mapping comment) |
| `modules/networking/outputs.tf` | config | — | same file (existing outputs) | exact (typed output, description convention) |

---

## Pattern Assignments

### `modules/efs/main.tf` (module, provision-once)

**Primary analog:** `modules/rds-tenant/main.tf`
**Secondary analog:** `modules/networking/main.tf` (SG with `security_groups` ingress, no CIDR)
**Tertiary analog:** `modules/rds-control-plane/main.tf` (identical SG-reference shape in a different module)

**Security group pattern — SG-reference ingress, NOT CIDR** (`modules/rds-tenant/main.tf` lines 10-30):
```hcl
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

Replicate for EFS: change `name_prefix` to `"${var.name_prefix}-efs-"`, change `description` to `"NFS from task SG only"`, change `from_port`/`to_port` to `2049`, change `tags.Name` to `"${var.name_prefix}-efs-sg"`. All other structural elements are identical.

**Original SG-reference pattern in networking module** (`modules/networking/main.tf` lines 88-108):
```hcl
# Task security group — only the ALB may reach Odoo on 8069 (SG reference, not CIDR — D-09).
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

**`count`-based conditional gating pattern** (`modules/rds-proxy/main.tf` lines 13-19 and 66-87):
```hcl
# count = var.enable_rds_proxy ? 1 : 0 pattern — not needed for EFS (always-on),
# but shows how gating works if ever needed. EFS resources are unconditional.
resource "aws_security_group" "proxy" {
  count       = var.enable_rds_proxy ? 1 : 0
  name_prefix = "${var.name_prefix}-rds-proxy-"
  vpc_id      = var.vpc_id
  ...
}
```

**`for_each` over a set/map pattern** — No existing `for_each` analog exists in the codebase today. The closest is `count` over `length(var.azs)` in `modules/networking/main.tf` lines 17-26:
```hcl
resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public-${var.azs[count.index]}" }
}
```

For mount targets, D-04 requires `for_each` over a subnet→AZ map (not `count`) to enforce the one-mount-target-per-AZ invariant. No existing `for_each` resource in the codebase — the planner must introduce it from the Terraform `for_each` pattern. The recommended approach per D-04 / Claude's Discretion: accept a `map(string)` variable `subnet_ids_by_az` (key = AZ, value = subnet id) and `for_each` mount targets over it. This keeps the plan fully offline (no `data "aws_subnet"` AZ lookup) and satisfies the dedup guard.

**Resource header comment style** (`modules/rds-tenant/main.tf` line 9):
```hcl
# Only ECS tasks may reach PostgreSQL on 5432 (SG reference, not CIDR — mirrors the networking module task SG pattern).
```

Apply same style above each EFS resource block explaining WHY, not WHAT.

**Tags — `Name` only, no extra tag blocks** (`modules/rds-tenant/main.tf` line 29):
```hcl
  tags = { Name = "${var.name_prefix}-rds-tenant-sg" }
```

Provider-level `default_tags` in `envs/prod/providers.tf` supplies Project/Environment/ManagedBy/Repo automatically. Modules add only `Name`.

---

### `modules/efs/variables.tf` (config)

**Primary analog:** `modules/rds-tenant/variables.tf`

**Variable structure pattern** (`modules/rds-tenant/variables.tf` lines 1-19):
```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the RDS DB subnet group. Requires >=2 subnets in different AZs."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC id for the RDS security group."
  type        = string
}

variable "task_security_group_id" {
  description = "Security group id for tenant ECS tasks. RDS SG allows 5432 ingress from this SG only."
  type        = string
}
```

EFS variables to declare (mirroring this shape):
- `name_prefix` — identical description/type.
- `vpc_id` — identical description/type (EFS SG needs it).
- `task_security_group_id` — identical description/type; update description to mention NFS/2049 instead of PostgreSQL/5432.
- For mount targets: either `subnet_ids` as `list(string)` (simple, relies on the one-subnet-per-AZ invariant comment) OR `subnet_ids_by_az` as `map(string)` (AZ→subnet-id, enables `for_each` dedup per D-04). Planner's discretion per Claude's Discretion section of CONTEXT.md.

**No `sensitive = true` on non-secret variables** — EFS variables are all non-sensitive (no passwords); the `sensitive = true` pattern in `modules/rds-tenant/variables.tf` line 24 applies only to `master_password`. Do NOT use it here.

**Defaults pattern** (`modules/rds-tenant/variables.tf` lines 27-49):
```hcl
variable "instance_class" {
  description = "RDS instance class for the tenant PostgreSQL instance."
  type        = string
  default     = "db.t4g.small"
}
```

EFS has no tunable performance variables that need defaults this phase. All variables are required (no default) because they all come from `module.networking.*` at the root level.

---

### `modules/efs/outputs.tf` (config)

**Primary analog:** `modules/ecs/outputs.tf` (single typed output, one-liner value)

**Single output pattern** (`modules/ecs/outputs.tf` lines 1-4):
```hcl
output "cluster_arn" {
  description = "Shared ECS cluster ARN for the tenant Fargate fleet."
  value       = aws_ecs_cluster.main.arn
}
```

Required output for EFS (`modules/efs/outputs.tf`):
```hcl
output "efs_id" {
  description = "Shared EFS filesystem id -> provisioner `aws_efs_id`."
  value       = aws_efs_file_system.<label>.id
}
```

**Provisioner mapping in description** (`modules/rds-tenant/outputs.tf` line 2):
```hcl
  description = "Shared tenant RDS endpoint -> provisioner `aws_shared_rds_endpoint`."
```

Replicate arrow-notation for `efs_id`: `"Shared EFS filesystem id -> provisioner \`aws_efs_id\`."`.

Optional additional outputs (Claude's Discretion, only if judged cheap/useful):
- `efs_arn` — same shape, `.arn` attribute; useful for IAM policies later.
- `efs_dns_name` — same shape, `.dns_name` attribute; useful for mount target DNS.

Do NOT add these unless the planner judges they are immediately needed by the provisioner contract. `efs_id` is the only contractually required output (EFS-02).

---

### `envs/prod/main.tf` (root wiring — uncomment and expand the `module "efs"` stub)

**Primary analog:** Existing `module "rds_tenant"` block in the same file (`envs/prod/main.tf` lines 43-54).

**Module call pattern** (`envs/prod/main.tf` lines 43-54):
```hcl
module "rds_tenant" {
  source                 = "../../modules/rds-tenant"
  name_prefix            = local.name_prefix
  subnet_ids             = module.networking.private_subnet_ids
  vpc_id                 = module.networking.vpc_id
  task_security_group_id = module.networking.task_security_group_id
  master_password        = module.ssm.tenant_rds_password
  instance_class         = var.rds_instance_class
  engine_version         = var.rds_engine_version
  allocated_storage      = var.rds_allocated_storage
  max_allocated_storage  = var.rds_max_allocated_storage
}
```

Expand the existing commented stub (lines 84-87 of `envs/prod/main.tf`):
```hcl
# module "efs" {
#   source      = "../../modules/efs"
#   name_prefix = local.name_prefix
# }
```

Into (exact argument names depend on which variable approach the planner picks for D-04):
```hcl
module "efs" {
  source                 = "../../modules/efs"
  name_prefix            = local.name_prefix
  vpc_id                 = module.networking.vpc_id
  task_security_group_id = module.networking.task_security_group_id
  # subnet_ids or subnet_ids_by_az — see D-04 / Claude's Discretion
}
```

Key rules from the analog:
- Module label uses underscores (`module "efs"` not `module "efs-filesystem"`).
- `source` path is relative from `envs/prod/` to `modules/efs`.
- `name_prefix = local.name_prefix` always first argument (established pattern).
- All networking refs via `module.networking.<output>` — never hardcoded values.
- No module-to-module calls; all wiring is here in `envs/prod/main.tf`.

**Placement:** The `module "efs"` block belongs in the `# --- 6. Filestore, routing/TLS` section, which is the correct build-order slot. It must be placed BEFORE `module "acm"` (also in that section).

---

### `envs/prod/outputs.tf` (root wiring — uncomment `efs_id` stub)

**Primary analog:** Existing uncommented outputs in the same file (`envs/prod/outputs.tf` lines 6-9 and 36-39).

**Output pattern** (`envs/prod/outputs.tf` lines 6-9):
```hcl
output "ecs_cluster_arn" {
  description = "Shared ECS cluster ARN -> provisioner `aws_ecs_cluster`."
  value       = module.ecs.cluster_arn
}
```

The commented stub to uncomment (lines 51-54 of `envs/prod/outputs.tf`):
```hcl
# output "efs_id" {
#   description = "Shared EFS id -> provisioner `aws_efs_id`."
#   value       = module.efs.efs_id
# }
```

Simply remove the `#` comment markers. The description and value reference are already correctly formed. No edits to content needed.

---

### `modules/networking/outputs.tf` (conditional — only if planner takes the AZ-map route for D-04)

**Primary analog:** Existing outputs in the same file (`modules/networking/outputs.tf` lines 1-19).

**Output pattern** (`modules/networking/outputs.tf` lines 6-9):
```hcl
output "private_subnet_ids" {
  description = "IDs of the public subnets tenant tasks run in."
  value       = aws_subnet.public[*].id
}
```

If the planner adds a `private_subnets_by_az` output to expose the AZ→subnet map:
```hcl
output "private_subnets_by_az" {
  description = "Map of AZ to public subnet id for EFS mount target per-AZ placement."
  value       = { for i, az in var.azs : az => aws_subnet.public[i].id }
}
```

This output is only needed if the EFS module accepts a `map(string)` variable. If the planner uses `subnet_ids` as `list(string)` with a `for_each` over an inline expression at the root level, this output is not needed. No change to `modules/networking/main.tf` is required in either case.

---

## Shared Patterns

### Resource naming — `${var.name_prefix}-<thing>`
**Source:** All modules, e.g. `modules/networking/main.tf` line 13, `modules/rds-tenant/main.tf` line 12.
**Apply to:** Every EFS resource block.
```hcl
  name_prefix = "${var.name_prefix}-efs-"   # for aws_security_group
  # or
  creation_token = "${var.name_prefix}-efs"  # for aws_efs_file_system
  tags = { Name = "${var.name_prefix}-efs" }
```

### Tags — `Name` only in module resources
**Source:** `modules/rds-tenant/main.tf` line 29, `modules/ecs/main.tf` line 21.
**Apply to:** All resources in `modules/efs/main.tf`.
```hcl
  tags = { Name = "${var.name_prefix}-<thing>" }
```

### SG-reference ingress (no CIDR)
**Source:** `modules/rds-tenant/main.tf` lines 14-20, `modules/networking/main.tf` lines 92-98.
**Apply to:** `aws_security_group.efs` ingress block.
```hcl
  ingress {
    description     = "NFS from task SG only"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.task_security_group_id] # NOT a CIDR
  }
```

### Standard egress block (allow-all outbound)
**Source:** `modules/rds-tenant/main.tf` lines 22-27, consistent across all SG resources.
**Apply to:** `aws_security_group.efs` egress block.
```hcl
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
```

### Module variable pre-declaration
**Source:** CONTEXT.md CONCERNS.md reference; pattern visible in `modules/rds-tenant/variables.tf`.
**Apply to:** `modules/efs/variables.tf` must declare ALL variables passed from `envs/prod/main.tf` BEFORE the `module "efs"` call is uncommented. An undeclared argument fails `terraform plan` with "unsupported argument".

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `aws_efs_file_system` resource | provision-once | — | No EFS resource exists in the codebase yet — this is the first. Use AWS provider docs for `performance_mode`, `throughput_mode`, `encrypted`, and `lifecycle_policy` block syntax. |
| `aws_efs_mount_target` resource | provision-once | — | No mount-target or per-AZ `for_each` resource exists yet. Planner must introduce `for_each` pattern from Terraform language docs. |
| `for_each` over `map(string)` | — | — | No `for_each` resource exists in the codebase (only `count` and `count = length(list)`). The `for_each` + map pattern must be written fresh. |

---

## Metadata

**Analog search scope:** `modules/`, `envs/prod/`, `bootstrap/`
**Files scanned:** 13 `.tf` files read directly; full file list enumerated (43 files)
**Pattern extraction date:** 2026-06-24
