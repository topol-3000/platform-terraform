# Phase 5: TLS and Routing — Pattern Map

**Mapped:** 2026-06-24
**Files analyzed:** 11 (9 module files + 2 env files + Makefile)
**Analogs found:** 11 / 11

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `modules/acm/main.tf` | module-resource | config | `modules/ecs/main.tf` | role-match (single resource, `name_prefix` unused in resource body, `lifecycle` block) |
| `modules/acm/variables.tf` | module-variables | config | `modules/networking/variables.tf` | exact (variable + `validation` block with `can()`) |
| `modules/acm/outputs.tf` | module-outputs | config | `modules/ecs/outputs.tf` | exact (single typed output, provisioner contract comment) |
| `modules/alb/main.tf` | module-resource | request-response | `modules/networking/main.tf` | role-match (multi-resource, SG + load resource, same `"${var.name_prefix}-<thing>"` naming) |
| `modules/alb/variables.tf` | module-variables | config | `modules/rds-tenant/variables.tf` | exact (multi-variable file: `name_prefix` + typed inputs, no defaults on required inputs) |
| `modules/alb/outputs.tf` | module-outputs | config | `modules/rds-tenant/outputs.tf` | exact (single required output + optional extras pattern) |
| `modules/route53/main.tf` | module-resource | config | `modules/ecs/main.tf` | role-match (single resource, domain-name-based identity not `name_prefix`, no `tags` block needed on zone) |
| `modules/route53/variables.tf` | module-variables | config | `modules/networking/variables.tf` | exact (variable + `validation` block with `can(regex(...))`) |
| `modules/route53/outputs.tf` | module-outputs | config | `modules/efs/outputs.tf` | exact (single typed output, provisioner contract comment) |
| `envs/prod/main.tf` | root-wiring | config | self (existing uncommented module blocks) | exact (uncomment-the-stub + expand-incomplete-stub pattern) |
| `envs/prod/outputs.tf` | root-outputs | config | self (existing active output blocks) | exact (uncomment three commented outputs) |
| `Makefile` (`plan-check` target) | build-config | config | self (existing `plan-check` target) | exact (add `-var` flag to `terraform plan` line) |

---

## Pattern Assignments

### `modules/acm/main.tf` (module-resource, config)

**Analog:** `modules/ecs/main.tf`

**File header comment pattern** (ecs lines 1–8):
```hcl
# Module: ecs
# Purpose: Shared ECS/Fargate cluster for the tenant fleet. ...
#
# SEED-001 note: ...
```
ACM header should follow identical structure. Replace `stub. No resources yet.` + `TODO:` with the implemented comment.

**Single-resource with `lifecycle` block** — analog from `modules/rds-tenant/main.tf` lines 40–51 (the only implemented `lifecycle { create_before_destroy = true }` pattern):
```hcl
resource "aws_db_parameter_group" "tenant" {
  name_prefix = "${var.name_prefix}-tenant-pg16-"
  family      = "postgres16"
  description = "Parameter group for the shared tenant PostgreSQL 16 instance."

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.name_prefix}-tenant-pg16" }
}
```

**ACM-specific: no `name` argument.** `aws_acm_certificate` is identified by `domain_name`, not `name`. Do not attempt `name = "${var.name_prefix}-cert"` — it will fail with "unsupported argument". The `name_prefix` module variable is accepted by convention but is NOT used in the `aws_acm_certificate` resource body. Pattern to follow:
```hcl
# Wildcard ACM certificate for *.{tenant_domain} — DNS validation; bare cert only (D-02).
# No aws_acm_certificate_validation resource (validation chain deferred; offline-plan-safe).
resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.tenant_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
```
No `tags = {}` block — provider `default_tags` applies tags (CONVENTIONS.md: no per-resource tags blocks).

---

### `modules/acm/variables.tf` (module-variables, config)

**Analog:** `modules/networking/variables.tf`

**`name_prefix` variable pattern** (networking lines 1–4) — identical across all modules:
```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}
```

**`validation` block pattern with `can()`** (networking lines 9–14):
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
```
For `tenant_domain`, replace `can(cidrhost(...))` with `can(regex(...))`. The double-backslash `\\.` is required because HCL strings treat `\` as an escape; `\\.` in HCL becomes `\.` in the regex engine (literal dot):
```hcl
variable "tenant_domain" {
  description = "Apex domain for the wildcard ACM certificate, e.g. \"saas.example.com\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))
    error_message = "tenant_domain must be a valid apex domain, e.g. saas.example.com."
  }
}
```
No `default` on `tenant_domain` — the root variable (`envs/prod/variables.tf` line 26) already defaults to `""` and carries the `# TODO:` marker. The module variable intentionally has no default so it fails loudly if not passed.

---

### `modules/acm/outputs.tf` (module-outputs, config)

**Analog:** `modules/ecs/outputs.tf` (lines 1–4):
```hcl
output "cluster_arn" {
  description = "Shared ECS cluster ARN for the tenant Fargate fleet."
  value       = aws_ecs_cluster.main.arn
}
```

**ACM output** — description must include the provisioner contract mapping (`-> provisioner \`aws_acm_cert_arn\``), matching the pattern from `modules/efs/outputs.tf` line 4:
```hcl
output "cert_arn" {
  description = "Wildcard ACM certificate ARN -> provisioner `aws_acm_cert_arn`."
  value       = aws_acm_certificate.wildcard.arn
}
```
Retain the header comment from the stub (`# Outputs for the acm module. Uncomment / add as resources are implemented;`).

---

### `modules/alb/main.tf` (module-resource, request-response)

**Analog:** `modules/networking/main.tf` — the richest multi-resource, multi-block analog in the codebase.

**Resource naming pattern** (networking lines 8, 17, 29, 36, 56, 88):
```hcl
# All resource names follow "${var.name_prefix}-<thing>" pattern.
tags = { Name = "${var.name_prefix}-alb-sg" }   # networking/main.tf line 83
tags = { Name = "${var.name_prefix}-vpc" }       # networking/main.tf line 14
```
For ALB resources: `"${var.name_prefix}-alb"` (the `aws_lb` name attribute, 18 chars — well within the 32-char AWS limit).

**No `tags = {}` per-resource** — `networking/main.tf` is the canonical example: it adds `tags = { Name = "..." }` only for the `Name` tag (the one that does NOT come from `default_tags`). However, per CONVENTIONS.md the project applies ALL tags via `default_tags` on the provider — review whether existing modules' `tags = { Name = "..." }` is the accepted exception. The pattern in rds-tenant, efs, networking, and ecs consistently uses `tags = { Name = "..." }` per resource, so follow this pattern.

**`aws_lb` resource structure**:
```hcl
# Shared internet-facing ALB — HTTPS termination and HTTP→HTTPS redirect for all tenant subdomains.
# idle_timeout > 60 required for Odoo longpoll (~50s); must be on aws_lb NOT aws_lb_listener.
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  idle_timeout               = 120   # > 60: Odoo longpoll ~50s guard (SEED-001)
  enable_deletion_protection = false
  enable_http2               = true
  drop_invalid_header_fields = true
  # No access_logs block — deferred hardening (D-04); no S3 bucket provisioned this phase.

  tags = { Name = "${var.name_prefix}-alb" }
}
```

**`aws_lb_listener` HTTP:80 redirect pattern**:
```hcl
# HTTP:80 — redirects all traffic to HTTPS:443 with 301. No ssl_policy or certificate_arn on HTTP listeners.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```

**`aws_lb_listener` HTTPS:443 fixed-response pattern**:
```hcl
# HTTPS:443 — TLS termination. default_action is 503 because no tenant target groups exist yet;
# the provisioner adapter attaches per-tenant host rules to this listener at provision time.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_cert_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "No tenant provisioned"
      status_code  = "503"
    }
  }
}
```

---

### `modules/alb/variables.tf` (module-variables, config)

**Analog:** `modules/rds-tenant/variables.tf` — multi-variable file with required inputs (no defaults) plus optional inputs with defaults.

**Required inputs pattern** (rds-tenant lines 1–19) — no `default`, no `validation`:
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
```

**ALB variables** — all required (no defaults); declare all before uncommenting the module call:
```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "acm_cert_arn" {
  description = "ARN of the wildcard ACM certificate for the HTTPS:443 listener."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the ALB (across >=2 AZs). Sourced from module.networking.private_subnet_ids."
  type        = list(string)
}

variable "security_group_id" {
  description = "ALB security group ID (allows ingress 80/443 from internet). Sourced from module.networking.alb_security_group_id."
  type        = string
}
```

---

### `modules/alb/outputs.tf` (module-outputs, config)

**Analog:** `modules/rds-tenant/outputs.tf` — one required contractual output + additional useful outputs.

**Pattern** (rds-tenant lines 1–4 — the primary contractual output):
```hcl
output "endpoint" {
  description = "Shared tenant RDS endpoint -> provisioner `aws_shared_rds_endpoint`."
  value       = aws_db_instance.tenant.endpoint
}
```

**ALB required output** — `listener_arn` is the HTTPS listener `.arn` attribute (not `.listener_arn`):
```hcl
output "listener_arn" {
  description = "HTTPS:443 listener ARN -> provisioner `aws_alb_listener_arn`."
  value       = aws_lb_listener.https.arn
}
```

---

### `modules/route53/main.tf` (module-resource, config)

**Analog:** `modules/ecs/main.tf` — single resource, minimal attributes, no inter-module dependencies.

**Single-resource pattern** (ecs lines 10–21):
```hcl
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"
  ...
  tags = { Name = "${var.name_prefix}-cluster" }
}
```

**Route53-specific:** `aws_route53_zone` has no `name` argument using `name_prefix` — the zone name IS the domain. No per-resource `tags = {}` block needed beyond what `default_tags` supplies:
```hcl
# Public hosted zone for tenant subdomains. No records declared here — the provisioner
# adapter adds per-tenant records at provision time (SEED-001; D-03).
resource "aws_route53_zone" "main" {
  name          = var.tenant_domain
  force_destroy = false
}
```

---

### `modules/route53/variables.tf` (module-variables, config)

**Analog:** `modules/networking/variables.tf` — exactly the same `validation` block pattern.

**Copy the same `tenant_domain` validation block** used in `modules/acm/variables.tf` (same regex, same error message). The `name_prefix` variable follows the standard single-variable pattern (same as every other module). Whether to include `name_prefix` is the planner's discretion: if included it must be declared here even if the resource body does not use it.

---

### `modules/route53/outputs.tf` (module-outputs, config)

**Analog:** `modules/efs/outputs.tf` (lines 1–7):
```hcl
# Outputs for the efs module. Uncomment / add as resources are implemented;
# envs/prod/outputs.tf re-exports the ones the provisioner adapter consumes.

output "efs_id" {
  description = "Shared EFS filesystem id -> provisioner `aws_efs_id`."
  value       = aws_efs_file_system.main.id
}
```

**Route53 output** — use `.zone_id` (explicit) rather than `.id` (both return the same value; `.zone_id` matches the output name `hosted_zone_id`):
```hcl
output "hosted_zone_id" {
  description = "Route53 hosted zone ID -> provisioner `aws_hosted_zone_id`."
  value       = aws_route53_zone.main.zone_id
}
```

---

### `envs/prod/main.tf` (root-wiring, uncomment + expand)

**Analog:** self — existing active module calls (e.g., `module "efs"` at lines 84–90) are the canonical pattern.

**Active module call pattern** (envs/prod/main.tf lines 84–90):
```hcl
module "efs" {
  source                 = "../../modules/efs"
  name_prefix            = local.name_prefix
  vpc_id                 = module.networking.vpc_id
  task_security_group_id = module.networking.task_security_group_id
  subnet_ids_by_az       = module.networking.private_subnets_by_az
}
```

**Stubs to uncomment and expand** (envs/prod/main.tf lines 93–108). The `alb` stub is **incomplete** — it lacks `subnet_ids` and `security_group_id`. The `route53` stub omits `name_prefix`. Expand as follows:

```hcl
# Build step 6 — Routing/TLS. acm MUST appear before alb (module.acm.cert_arn dependency).
module "acm" {
  source        = "../../modules/acm"
  name_prefix   = local.name_prefix
  tenant_domain = var.tenant_domain
}

module "alb" {
  source            = "../../modules/alb"
  name_prefix       = local.name_prefix
  acm_cert_arn      = module.acm.cert_arn
  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.networking.alb_security_group_id
}

module "route53" {
  source        = "../../modules/route53"
  name_prefix   = local.name_prefix
  tenant_domain = var.tenant_domain
}
```

Key points:
- `module.networking.private_subnet_ids` is the public subnet list (named under that contract per `networking/outputs.tf` line 7).
- `module.networking.alb_security_group_id` is already active (`networking/outputs.tf` line 16).
- Remove the comment markers (`#`) from both the opening `#` lines and the closing `#` lines of each stub block.

---

### `envs/prod/outputs.tf` (root-outputs, uncomment)

**Analog:** self — existing active output blocks (lines 6–9 `ecs_cluster_arn`, lines 36–39 `tenant_rds_endpoint`).

**Active output pattern** (envs/prod/outputs.tf lines 6–9):
```hcl
output "ecs_cluster_arn" {
  description = "Shared ECS cluster ARN -> provisioner `aws_ecs_cluster`."
  value       = module.ecs.cluster_arn
}
```

**Three outputs to uncomment** (current lines 31–34, 56–59, 61–64):
```hcl
output "alb_listener_arn" {
  description = "ALB HTTPS listener ARN -> provisioner `aws_alb_listener_arn`."
  value       = module.alb.listener_arn
}

output "hosted_zone_id" {
  description = "Route53 zone id -> provisioner `aws_hosted_zone_id`."
  value       = module.route53.hosted_zone_id
}

output "acm_cert_arn" {
  description = "Wildcard ACM cert ARN -> provisioner `aws_acm_cert_arn`."
  value       = module.acm.cert_arn
}
```
Remove only the `# ` prefix from each line of the three comment blocks (lines 31–34, 56–59, 61–64). The descriptions are already correct in the stub.

---

### `Makefile` (`plan-check` target)

**Analog:** self — the existing `plan-check` target (Makefile lines 31–48).

**Current `terraform plan` line** (Makefile line 48):
```makefile
		terraform plan -input=false
```

**Required change** — add `-var "tenant_domain=placeholder.example.com"` so the regex `validation` block in `modules/acm/variables.tf` and `modules/route53/variables.tf` does not reject the empty-string root default:
```makefile
		terraform plan -input=false -var "tenant_domain=placeholder.example.com"
```

`placeholder.example.com` satisfies the regex `^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$`, is plainly a non-real domain, and is safe to commit in the Makefile. This is the only change to `plan-check`.

---

## Shared Patterns

### `name_prefix` convention
**Source:** Every module `variables.tf` (canonical: `modules/ecs/variables.tf` line 1–4)
**Apply to:** All three new module `variables.tf` files
```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}
```
All resource `name` / `name_prefix` attributes use `"${var.name_prefix}-<thing>"`. Exception: `aws_acm_certificate` has no `name` argument; `aws_route53_zone` uses `name = var.tenant_domain` (domain-based identity).

### `validation` block with `can()` idiom
**Source:** `modules/networking/variables.tf` lines 9–14; `envs/prod/variables.tf` lines 30–37
**Apply to:** `modules/acm/variables.tf` and `modules/route53/variables.tf` (both `tenant_domain` variables)
```hcl
validation {
  condition     = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))
  error_message = "tenant_domain must be a valid apex domain, e.g. saas.example.com."
}
```
`can(regex(...))` returns `false` (not an error) when the pattern does not match — this is the correct idiom. Double-backslash `\\.` is required in HCL string context.

### No per-resource `tags = {}` blocks
**Source:** CONVENTIONS.md; `modules/ecs/main.tf` (no `tags` block at all — `aws_ecs_cluster` gets only `tags = { Name = "..." }`)
**Apply to:** All new module resources
All tagging is via provider `default_tags`. The `tags = { Name = "..." }` block is the accepted pattern for setting the `Name` tag (which `default_tags` does not set). `aws_acm_certificate` and `aws_route53_zone` do not need `Name` tags (ACM is identified by `domain_name`; Route53 zone by domain). `aws_lb` and `aws_lb_listener` resources: follow networking/rds-tenant pattern and add `tags = { Name = "${var.name_prefix}-alb" }` etc. on `aws_lb` only; listeners typically do not get Name tags.

### Output description convention — provisioner contract mapping
**Source:** `modules/efs/outputs.tf` line 4; `modules/rds-tenant/outputs.tf` line 2
**Apply to:** All three new module `outputs.tf` files and the three uncommented root outputs
```
"<What it is> -> provisioner `<setting_name>`."
```

### Module file header comment structure
**Source:** `modules/ecs/main.tf` lines 1–8; `modules/efs/main.tf` lines 1–7
**Apply to:** All three new module `main.tf` files
```hcl
# Module: <name>
# Purpose: <one sentence>
#
# SEED-001 note: <relevant constraint or future note>
#
# STATUS: implemented.
# See ../../../provisioner/.planning/seeds/SEED-001-aws-real-deployment.md
```
Remove the `# TODO:` line from current stubs.

### `lifecycle { create_before_destroy = true }` pattern
**Source:** `modules/rds-tenant/main.tf` lines 45–49
**Apply to:** `modules/acm/main.tf` (`aws_acm_certificate` resource)
Standard ACM practice for zero-downtime cert rotation; free and offline-safe. No equivalent is needed in route53 or alb resources.

---

## No Analog Found

All files for Phase 5 have close analogs in the codebase. No files require falling back to RESEARCH.md patterns exclusively.

| File | Note |
|---|---|
| `modules/alb/main.tf` (listener resources) | `aws_lb_listener` with `fixed_response` / `redirect` default actions have no exact existing analog, but the `networking/main.tf` multi-resource module structure is the structural analog. The exact resource syntax is covered in RESEARCH.md Patterns 3 and 4. |

---

## Metadata

**Analog search scope:** `modules/*/`, `envs/prod/`, `bootstrap/`, `Makefile`
**Files read:** 25 (all module main/variables/outputs + env files + Makefile)
**Pattern extraction date:** 2026-06-24
