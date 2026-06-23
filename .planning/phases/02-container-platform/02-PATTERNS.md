# Phase 2: Container platform - Pattern Map

**Mapped:** 2026-06-23
**Files analyzed:** 8 (2 new module main.tf, 2 module outputs.tf, 2 module variables.tf, 2 root files edited)
**Analogs found:** 8 / 8 (all exact — same repo, same module-interface pattern)

## File Classification

Terraform has no "controllers/services". Roles are mapped to Terraform layer roles; data flow is mapped to Terraform value flow (input variable -> resource -> output, and module -> root wiring).

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `modules/ecr/main.tf` | module (resource layer) | input-var -> resource -> attr | `modules/networking/main.tf` + `bootstrap/main.tf` | exact (canonical module pattern) |
| `modules/ecr/outputs.tf` | module output (contract) | resource attr -> output | `modules/networking/outputs.tf` | exact |
| `modules/ecr/variables.tf` | module input | root -> var | `modules/networking/variables.tf` | exact |
| `modules/ecs/main.tf` | module (resource layer) | input-var -> resource -> attr | `modules/networking/main.tf` | exact |
| `modules/ecs/outputs.tf` | module output (contract) | resource attr -> output | `modules/networking/outputs.tf` | exact |
| `modules/ecs/variables.tf` | module input | root -> var | `modules/networking/variables.tf` | exact |
| `envs/prod/main.tf` (edit) | root composition | module wiring | the live `module "networking"` block (lines 14-20) | exact |
| `envs/prod/outputs.tf` (edit) | root output (provisioner contract) | module output -> root output | the live `private_subnet_ids` block (lines 11-14) | exact |

---

## Pattern Assignments

### `modules/ecr/main.tf` (module, resource layer)

**Primary analog:** `modules/networking/main.tf` (canonical module file structure). Secondary: `bootstrap/main.tf` (multi-resource-same-label labeling, used by ECR's repo + lifecycle-policy pair).

**File-header comment pattern** — every module `main.tf` opens with `# Module:`, `# Purpose:`, and a SEED-001 note. The stub already carries this (`modules/ecr/main.tf` lines 1-9) but its content is the REJECTED pull-through-cache wording. Per D-01 the header must be rewritten to describe a **managed `aws_ecr_repository`** and the comment must NOT reference GHCR pull-through. Pattern to mirror (from `modules/networking/main.tf` lines 1-5):
```hcl
# Module: networking
# Purpose: VPC, public subnets (NO NAT gateway), internet gateway, route table, and security groups
#
# SEED-001 note: Public subnets only, no NAT (cost). Tenant task SG must accept 8069 ONLY
# from the ALB SG id — the sole guard against direct internet exposure of tasks on public subnets.
```

**Resource-naming + Name-tag pattern** (every resource in `modules/networking/main.tf`, e.g. line 8-14):
```hcl
# <single-line comment explaining WHY this resource exists>
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # inline comment only for non-obvious values
  ...
  tags = { Name = "${var.name_prefix}-vpc" }
}
```
Apply to ECR: resource label is the logical role (e.g. `aws_ecr_repository "odoo_core"`), `name = "${var.name_prefix}-odoo-core"` (D-01 discretion), `tags = { Name = "${var.name_prefix}-odoo-core" }`. Only a `Name` tag — Project/Environment/ManagedBy/Repo come from provider `default_tags` (see Shared Patterns / never re-declare them).

**Multi-resource-same-label pattern** (from `bootstrap/main.tf` lines 5, 16, 25, 37, 47) — supporting resources for one logical object share the label of the primary resource:
```hcl
resource "aws_s3_bucket"                          "tfstate" { ... }
resource "aws_s3_bucket_versioning"               "tfstate" { ... }
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" { ... }
```
Apply to ECR: the `aws_ecr_lifecycle_policy` (expire untagged images — D-32 discretion) shares the repo's label and references it by attribute: `repository = aws_ecr_repository.<label>.name`.

**Hardening defaults to include (Claude's Discretion D-32):** `image_scanning_configuration { scan_on_push = true }`, `image_tag_mutability`, AES256 encryption (KMS deferred), `aws_ecr_lifecycle_policy` to expire untagged images. Each non-obvious block gets a one-line WHY comment (cost / hygiene).

**No data sources / no STS (D-02, D-07):** `image_uri` derives from the resource attribute `repository_url`. Do NOT add `data "aws_caller_identity"` or build an account-id string — that would break the offline `make plan-check` gate.

---

### `modules/ecr/outputs.tf` (module output, contract)

**Analog:** `modules/networking/outputs.tf` (entire file, lines 1-19).

The stub (`modules/ecr/outputs.tf`) is just a comment header — replace it with real outputs. Output pattern (from `modules/networking/outputs.tf` lines 1-4):
```hcl
output "vpc_id" {
  description = "VPC id for downstream modules (rds, ecs, alb)."
  value       = aws_vpc.main.id
}
```
Apply to ECR — the root wiring expects `module.ecr.image_uri` (see `envs/prod/main.tf` commented block line 23-26 and `envs/prod/outputs.tf` line 61-64):
```hcl
output "image_uri" {
  description = "ECR repository URL for the odoo-core image; adapter appends the deployed tag."
  value       = aws_ecr_repository.<label>.repository_url
}
```
Description rules (CONVENTIONS): one sentence, ends with a period, states what it IS. No `sensitive` annotation (repo URL is not a secret).

---

### `modules/ecr/variables.tf` (module input)

**Analog:** `modules/networking/variables.tf` lines 1-4 (the `name_prefix` block — copy verbatim).
```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}
```
The stub already contains exactly this. Per D-03 no `account_id` / `credential_arn` variables are needed. Only add further variables if a hardening default must be parameterized (unlikely — prefer literals with WHY comments per D-32). If a variable is added, follow the networking `validation {}` block style (lines 10-13) where a constraint is meaningful.

---

### `modules/ecs/main.tf` (module, resource layer)

**Analog:** `modules/networking/main.tf` (file structure, header, naming, Name-tag, WHY comments — same as ECR above).

The stub header (`modules/ecs/main.tf` lines 1-9) is close to correct intent ("Shared ECS cluster for the Fargate tenant fleet") but rewrite the STATUS/TODO lines and keep a SEED-001 note. Resources required per D-04:
```hcl
# aws_ecs_cluster — name = "${var.name_prefix}-..." ; setting { name="containerInsights" value="enabled|enhanced" }  (D-04, value style is discretion)
# aws_ecs_cluster_capacity_providers — capacity_providers = ["FARGATE", "FARGATE_SPOT"] ; references the cluster by .name attribute
```
Label-sharing pattern (bootstrap): the `aws_ecs_cluster_capacity_providers` shares the cluster's logical label and references `cluster_name = aws_ecs_cluster.<label>.name`. Name tag: `tags = { Name = "${var.name_prefix}-..." }`. Whether to set `default_capacity_provider_strategy` is Claude's Discretion (D-04). No data sources (offline-plan rule, D-07).

---

### `modules/ecs/outputs.tf` (module output, contract)

**Analog:** `modules/networking/outputs.tf` lines 1-4.

Root wiring expects `module.ecs.cluster_arn` (see `envs/prod/main.tf` line 29-32 and `envs/prod/outputs.tf` line 6-9):
```hcl
output "cluster_arn" {
  description = "Shared ECS cluster ARN for the tenant Fargate fleet."
  value       = aws_ecs_cluster.<label>.arn
}
```

---

### `modules/ecs/variables.tf` (module input)

**Analog:** `modules/networking/variables.tf` lines 1-4 — the `name_prefix` block (already present in the stub, copy verbatim). No additional inputs required (ECS consumes no networking outputs — CONTEXT integration note).

---

### `envs/prod/main.tf` (root composition — EDIT, do not rewrite)

**Analog:** the live `module "networking"` block in the same file (lines 14-20):
```hcl
# --- 2. Networking: VPC, public subnet (NO NAT gateway), security groups ------
module "networking" {
  source      = "../../modules/networking"
  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
}
```
Action: uncomment the existing step-3 `module "ecr"` block (lines 23-26) and step-4 `module "ecs"` block (lines 29-32). They already have the correct shape:
```hcl
module "ecr" {
  source      = "../../modules/ecr"
  name_prefix = local.name_prefix
}
module "ecs" {
  source      = "../../modules/ecs"
  name_prefix = local.name_prefix
}
```
Module label uses underscores (`ecr`, `ecs` are single words; `rds_control_plane` shows the underscore rule). `name_prefix = local.name_prefix` is the sole required input (CONTEXT reusable asset). Modules call no other modules — neither block references `module.networking.*` (ECR/ECS consume no networking outputs).

### `envs/prod/outputs.tf` (provisioner contract — EDIT, do not rewrite)

**Analog:** the live `private_subnet_ids` output in the same file (lines 11-14):
```hcl
output "private_subnet_ids" {
  description = "Subnets for tenant tasks -> provisioner `aws_subnets`."
  value       = module.networking.private_subnet_ids
}
```
Action: uncomment the existing `ecs_cluster_arn` block (lines 6-9) and `ecr_image_uri` block (lines 61-64). The `ecr_image_uri` description still says "pull-through image URI" — update it per D-01/D-02 to describe the managed repository URL:
```hcl
output "ecs_cluster_arn" {
  description = "Shared ECS cluster ARN -> provisioner `aws_ecs_cluster`."
  value       = module.ecs.cluster_arn
}
output "ecr_image_uri" {
  description = "ECR repository URL for odoo-core -> provisioner `aws_ecr_image`."
  value       = module.ecr.image_uri
}
```
Description contract (CONVENTIONS): `<What it is> -> provisioner \`<setting_name>\`.` These map 1:1 to `AwsDeploymentAdapter` settings.

---

## Shared Patterns

### Tagging — `default_tags` only
**Source:** `envs/prod/providers.tf` lines 4-11.
**Apply to:** every resource in `modules/ecr/main.tf` and `modules/ecs/main.tf`.
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
Modules must NOT re-declare Project/Environment/ManagedBy/Repo. Add only a `Name` tag per resource: `tags = { Name = "${var.name_prefix}-<thing>" }`. Confirmed by networking — every resource carries only a `Name` tag.

### Resource naming
**Source:** `modules/networking/main.tf` (all resources).
**Apply to:** all ECR/ECS resources.
Every resource name/identifier is `"${var.name_prefix}-<thing>"` — never hardcoded. Resource *label* = logical role, not resource type (e.g. `aws_ecr_repository "odoo_core"`, not `"repository"`). snake_case throughout.

### WHY-comments
**Source:** `bootstrap/main.tf` (lines 8-9, 24, 36, 46) and `modules/networking/main.tf` (lines 10, 23, 97, 104).
**Apply to:** every non-obvious resource (one-line comment above explaining WHY) and sparingly inline on non-obvious attribute values.

### Module versions.tf
**Source:** networking module has NO `versions.tf` (confirmed — `Read` of `modules/networking/versions.tf` returned file-not-found).
**Apply to:** ECR/ECS modules — do NOT add a `versions.tf`. Modules inherit `required_providers` / `required_version` from the root `envs/prod/versions.tf`. The standard module file set here is `main.tf` + `variables.tf` + `outputs.tf` only.

### Offline-plan gate (D-07)
**Source:** D-06/D-07 (Phase 1) + the absence of any `data` blocks in networking.
**Apply to:** ECR and ECS — introduce NO `data` sources (no `aws_caller_identity`, no `aws_ecr_authorization_token`). Derive `image_uri` from `repository_url` attribute. Verification is `make plan-check` (offline), NOT `make plan` (see auto-memory: terraform offline plan gate).

---

## No Analog Found

None. All eight files map exactly to the implemented Phase 1 networking module and the established root-wiring pattern in the same repo. The only adjustments are domain-specific resource bodies (ECR repo / ECS cluster), for which the AWS provider `~> 6.0` resource schemas apply — but the structure, naming, tagging, comment, output, and wiring conventions are all covered by in-repo analogs.

## Metadata

**Analog search scope:** `modules/networking/`, `modules/ecr/`, `modules/ecs/`, `envs/prod/`, `bootstrap/`
**Files scanned:** 13 read (3 networking, 6 ecr/ecs stubs, 4 root incl. providers + bootstrap main)
**Pattern extraction date:** 2026-06-23
