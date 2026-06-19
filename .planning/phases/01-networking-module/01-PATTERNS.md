# Phase 1: networking-module - Pattern Map

**Mapped:** 2026-06-19
**Files analyzed:** 7 (3 module files, 3 root-config files, 1 Makefile)
**Analogs found:** 7 / 7

All files have strong in-repo analogs. This is a small, highly consistent HCL
codebase: `bootstrap/` is the canonical resource-block reference, `envs/prod/`
is the canonical root-config reference, and the module stubs define the scaffold
contract. The planner should copy directly from these — there is no need to fall
back to RESEARCH.md patterns for any file.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `modules/networking/main.tf` | module (resources) | transform (inputs → AWS resources) | `bootstrap/main.tf` | role-match (resource-block style; different AWS services) |
| `modules/networking/variables.tf` | module (inputs) | request-response (typed inputs) | `bootstrap/variables.tf` + `modules/networking/variables.tf` (existing `name_prefix` stub) | exact |
| `modules/networking/outputs.tf` | module (outputs) | request-response (typed outputs) | `envs/prod/outputs.tf` (output style) | role-match |
| `envs/prod/main.tf` | config (module wiring) | transform (locals → module call) | `envs/prod/main.tf` (existing commented `module "networking"` block) | exact (uncomment + extend) |
| `envs/prod/outputs.tf` | config (output re-export) | request-response | `envs/prod/outputs.tf` (existing commented outputs) | exact (uncomment + add) |
| `envs/prod/variables.tf` | config (inputs) | request-response | `envs/prod/variables.tf` (existing `region`/`tenant_domain` vars) | exact |
| `Makefile` | config (workflow) | batch (CLI wrapper) | `Makefile` `plan` target | exact (extend existing target) |

## Pattern Assignments

### `modules/networking/main.tf` (module, transform)

**Analog:** `bootstrap/main.tf` — the canonical resource-block style for this repo.

**Header comment pattern** — extend the existing stub header at
`modules/networking/main.tf` lines 1-10; keep the `# Module: networking` /
`# Purpose:` / SEED-001 note format, drop the `STATUS: stub` / `TODO` lines once
implemented.

**WHY-comment + label conventions** (`bootstrap/main.tf` lines 5-13) — every
resource gets a single-line comment above it explaining WHY (not what), and the
resource label is the logical role, not the AWS type:
```hcl
# State is the source of truth for live infrastructure — guard against an
# accidental `terraform destroy` of the bootstrap itself.
resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
  ...
}
```
Apply: label networking resources by role, e.g. `aws_vpc.main`,
`aws_subnet.public`, `aws_internet_gateway.main`, `aws_route_table.public`,
`aws_security_group.alb`, `aws_security_group.task`.

**Supporting-resources-share-label pattern** (`bootstrap/main.tf` lines 5, 16,
25, 37, 47 — `aws_s3_bucket.tfstate` + `aws_s3_bucket_versioning.tfstate` +
`aws_s3_bucket_public_access_block.tfstate` all share label `tfstate`):
```hcl
resource "aws_s3_bucket" "tfstate"            { ... }
resource "aws_s3_bucket_versioning" "tfstate" { ... }
```
Apply: route-table + association share a label; SG + its rules (if split into
`aws_security_group_rule`) share the resource's logical label.

**name_prefix prefixing (CONTEXT D-13)** — every resource Name/identifier is
`"${var.name_prefix}-<thing>"`. `bootstrap` uses `var.state_bucket_name`
directly; networking must interpolate `name_prefix`:
```hcl
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags       = { Name = "${var.name_prefix}-vpc" }
}
```
Note: `default_tags` (Project/Environment/ManagedBy/Repo) is set in
`envs/prod/providers.tf` lines 4-11 and inherited automatically — the module adds
ONLY the per-resource `Name` tag. No other `tags = {}` keys.

**Subnet fan-out (CONTEXT D-02/D-04/D-05)** — one public subnet per AZ from the
`azs` list variable, CIDR via `cidrsubnet`. `count` vs `for_each` is Claude's
discretion (D). No `data.aws_availability_zones` (D-04 — keeps plan offline):
```hcl
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)  # /16 -> /20
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true   # no NAT -> tasks need public IPs for egress
  tags                    = { Name = "${var.name_prefix}-public-${var.azs[count.index]}" }
}
```

**Security-group cross-reference (CONTEXT D-08/D-09)** — task SG ingress
references the ALB SG **id**, not a CIDR. This is the load-bearing rule the plan
must show:
```hcl
resource "aws_security_group" "task" {
  name_prefix = "${var.name_prefix}-task-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8069
    to_port         = 8069
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]   # NOT a CIDR (D-09)
  }
  egress {                                          # allow-all for now (D-10)
    from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name_prefix}-task-sg" }
}
```
ALB SG ingress: ports 80 AND 443 from `0.0.0.0/0`, egress allow-all (D-08).

**Error-handling / lifecycle** — `bootstrap/main.tf` lines 10-12 show the
`lifecycle { prevent_destroy = true }` pattern. NOT needed for networking
resources (they are recreatable); no lifecycle blocks required this phase.

---

### `modules/networking/variables.tf` (module, request-response)

**Analog:** existing `modules/networking/variables.tf` (the `name_prefix` stub,
already correct) + `bootstrap/variables.tf` for typed/defaulted variables.

**Existing `name_prefix` stub — keep verbatim** (`modules/networking/variables.tf`
lines 1-4):
```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}
```

**Typed variable with default** (`bootstrap/variables.tf` lines 17-21):
```hcl
variable "noncurrent_version_expiration_days" {
  description = "Delete noncurrent (overwritten) state versions after this many days."
  type        = number
  default     = 90
}
```
Apply to `vpc_cidr` (default `"10.0.0.0/16"`, D-01) and `azs`
(`type = list(string)`, default `["eu-central-1a", "eu-central-1b"]`, D-04).
Description ends with a period (CONVENTION).

**Validation blocks (CONTEXT D-12)** — NO existing `validation {}` block exists
in the repo (per CLAUDE.md "no validation blocks present"). This phase
introduces the first ones. Standard HCL form:
```hcl
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "azs" {
  description = "Availability zones to place one public subnet in each."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two AZs are required (future ALB needs >=2 subnets)."
  }
}
```

---

### `modules/networking/outputs.tf` (module, request-response)

**Analog:** `envs/prod/outputs.tf` lines 1-19 (output naming + description
style). The existing module stub (`modules/networking/outputs.tf` lines 1-2) is
just a comment header — replace with real outputs.

**Output naming must match the provisioner contract** — the root re-export in
`envs/prod/outputs.tf` references `module.networking.private_subnet_ids` (line
13) and `module.networking.task_security_group_id` (line 18). Module outputs
MUST be named exactly these (CONTEXT D-03: public subnets exported under
`private_subnet_ids` so the contract is unchanged):
```hcl
output "private_subnet_ids" {
  description = "IDs of the public subnets tenant tasks run in."
  value       = aws_subnet.public[*].id
}

output "task_security_group_id" {
  description = "Security group id for tenant ECS tasks."
  value       = aws_security_group.task.id
}

output "vpc_id" {
  description = "VPC id for downstream modules (rds, ecs, alb)."
  value       = aws_vpc.main.id
}

output "alb_security_group_id" {
  description = "Security group id for the shared ALB."
  value       = aws_security_group.alb.id
}
```
Description ends with a period; states what the value IS (CONVENTION).

---

### `envs/prod/main.tf` (config, transform — module wiring)

**Analog:** the existing commented `module "networking"` block
(`envs/prod/main.tf` lines 13-17). Uncomment and extend with the new inputs.

**locals.name_prefix is already defined** (`envs/prod/main.tf` lines 9-11) — pass
it through, do NOT redefine:
```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"
}
```

**Module-call pattern** (extend lines 13-17) — `source` + `name_prefix` are
already there; add `vpc_cidr` and `azs` wired from root variables. All wiring
lives here; the module calls no other module (CLAUDE.md anti-pattern):
```hcl
# --- 2. Networking: VPC, public subnets (NO NAT gateway), security groups -----
module "networking" {
  source      = "../../modules/networking"
  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
}
```
Note the existing `=`-alignment within the block (terraform fmt output). Leave
the downstream commented module blocks (ecr/ecs/rds...) as-is.

---

### `envs/prod/outputs.tf` (config, request-response — output re-export)

**Analog:** existing commented outputs in `envs/prod/outputs.tf` (lines 11-19).
Uncomment `private_subnet_ids` and `task_security_group_id`; add `vpc_id` /
`alb_security_group_id` following the same form.

**Re-export pattern with downstream-consumer note in the description** (lines
11-19 — the `-> provisioner \`<setting>\`` mapping is a required convention):
```hcl
output "private_subnet_ids" {
  description = "Subnets for tenant tasks -> provisioner `aws_subnets`."
  value       = module.networking.private_subnet_ids
}

output "task_security_group_id" {
  description = "SG for tenant tasks -> provisioner `aws_security_groups`."
  value       = module.networking.task_security_group_id
}
```
For the two NEW outputs (`vpc_id`, `alb_security_group_id`) that have no
provisioner-contract mapping yet, describe them as internal/downstream wiring:
```hcl
output "vpc_id" {
  description = "VPC id -> consumed by downstream rds/ecs/alb modules."
  value       = module.networking.vpc_id
}
```
Leave the still-uncommented outputs for unbuilt modules (ecs/alb/rds...)
commented out.

---

### `envs/prod/variables.tf` (config, request-response)

**Analog:** existing variables in `envs/prod/variables.tf` — `region` (lines 1-5)
for the simple defaulted form, `tenant_domain` (lines 19-27) for the
heredoc-description form.

**Simple defaulted variable** (lines 1-5):
```hcl
variable "region" {
  description = "AWS region for the prod baseline. Must match the state bucket region."
  type        = string
  default     = "eu-central-1"
}
```
Add `vpc_cidr` (default `"10.0.0.0/16"`) and `azs`
(`type = list(string)`, default `["eu-central-1a", "eu-central-1b"]`) here with
prod-sensible defaults (CONTEXT D-11 — `make plan` runs with zero tfvars
editing). These are the root-level passthroughs wired in `main.tf`.

---

### `Makefile` (config, batch — workflow wrapper)

**Analog:** existing `plan` target (`Makefile` lines 19-20).

**Existing target** (lines 19-20):
```makefile
plan: ## terraform plan for $(ENV)
	cd $(ENV_DIR) && terraform plan
```

**Pattern to apply (CONTEXT D-06)** — prefix the `terraform plan` invocation with
inline dummy AWS env so the plan succeeds offline (no data sources, no state to
refresh → provider initializes but makes no real API calls). Do NOT touch
`providers.tf` (D-07 — provider stays clean for real applies):
```makefile
plan: ## terraform plan for $(ENV) (offline: dummy AWS creds)
	cd $(ENV_DIR) && AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy AWS_REGION=eu-central-1 terraform plan
```
Keep tab indentation (Makefile recipe lines must use tabs, not spaces). Leave
`apply`/`destroy` targets unchanged — only `plan` (and any plan-only target)
gets the dummy env.

## Shared Patterns

### name_prefix prefixing
**Source:** `envs/prod/main.tf` lines 9-11 (`local.name_prefix`), threaded into
every module. **Apply to:** all `modules/networking` resources — every Name tag
and `name_prefix` argument is `"${var.name_prefix}-<thing>"`. Never hardcode the
`odoo-saas-prod` string in the module (CLAUDE.md anti-pattern).

### Tagging via default_tags only
**Source:** `envs/prod/providers.tf` lines 4-11.
```hcl
default_tags {
  tags = {
    Project     = "odoo-saas"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repo        = "platform-terraform"
  }
}
```
**Apply to:** all module resources — they inherit Project/Environment/ManagedBy/
Repo automatically. The module adds ONLY a per-resource `Name` tag. No other
`tags = {}` keys (CLAUDE.md: "Applied exclusively via provider-level
default_tags — no per-resource tags blocks", with `Name` as the documented
exception for identifying resources).

### WHY-comments + logical-role labels
**Source:** `bootstrap/main.tf` (lines 8-9, 15, 24, 36, 46). **Apply to:**
`modules/networking/main.tf` — single-line comment above each non-obvious
resource explaining intent (e.g. `# No NAT -> public subnets give tasks egress
via public IPs`), and resource labels reflect the logical role
(`aws_subnet.public`, not `aws_subnet.subnet`).

### versions.tf — module has none; root owns provider constraints
**Source:** no `modules/*/versions.tf` exists (verified — `find modules -name
versions.tf` returns nothing); `envs/prod/versions.tf` lines 1-10 holds the
`required_version >= 1.11.0` + `aws ~> 6.0` constraints. **Apply to:** do NOT add
a `versions.tf` to `modules/networking` — match the established convention where
modules inherit provider constraints from the calling root.

### Description style
**Source:** `bootstrap/variables.tf` + `envs/prod/outputs.tf`. **Apply to:** all
new variables and outputs — description ends with a period, states what the
thing IS (not how to use it); multi-line guidance uses `<<-EOT` heredoc
(`envs/prod/variables.tf` lines 20-25); output descriptions that feed the
provisioner include the `-> provisioner \`<setting>\`` mapping.

## No Analog Found

None. Every file in this phase maps to an existing in-repo pattern.

The ONE genuinely new construct is the `validation {}` block (CONTEXT D-12) —
the repo has no prior example (confirmed in CLAUDE.md: "No validation blocks
present in any variable"). Standard HCL `validation { condition / error_message }`
form is given inline under `modules/networking/variables.tf` above; planner does
not need RESEARCH.md for it.

## Metadata

**Analog search scope:** `bootstrap/`, `envs/prod/`, `modules/*/`, `Makefile` (full repo — small codebase, exhaustively scanned)
**Files scanned:** 11 (bootstrap: main/variables/versions; envs/prod: main/outputs/variables/providers/versions; modules/networking: main/variables/outputs; Makefile; sampled modules/alb + modules/acm variables.tf)
**Pattern extraction date:** 2026-06-19
