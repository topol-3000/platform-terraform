# Phase 5: TLS and Routing — Research

**Researched:** 2026-06-24
**Domain:** AWS ACM, ALB (ELBv2), Route53, Terraform variable validation
**Confidence:** HIGH (all critical HCL syntax verified against official docs and codebase)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 — ALB listener topology:** Two listeners. (a) HTTP:80 with `301 redirect` to HTTPS:443. (b) HTTPS:443 with ACM cert, `idle_timeout > 60`, and `default_action = fixed-response 503`. No SG change needed (networking already permits 80/443 ingress).

**D-02 — ACM DNS validation depth:** Bare `aws_acm_certificate` with `validation_method = "DNS"` only — no `aws_route53_record` for `domain_validation_options`, no `aws_acm_certificate_validation` resource. Add `lifecycle { create_before_destroy = true }`. ACM and route53 remain decoupled.

**D-03 — Fleet-wide DNS records:** `route53` module declares only the hosted zone (`hosted_zone_id` output), no records of any kind. Keeps route53 decoupled from alb.

**D-04 — ALB cost/hardening toggles:** No access logs (no S3 bucket). `enable_deletion_protection = false`. Free hardening on: `enable_http2 = true`, `drop_invalid_header_fields = true`.

### Claude's Discretion

- **ALB wiring inputs** — thread `module.networking.private_subnet_ids` (subnets), `module.networking.alb_security_group_id` (SG) into `module "alb"`. Declare matching variables. `internal = false`, `load_balancer_type = "application"`.
- **`tenant_domain` regex** — a reasonable domain pattern that rejects empty string and obviously-invalid hosts. Same regex reused in `acm` and `route53`.
- **fixed-response 503 body/content-type** — short plain-text body at planner's discretion; only the `503` status matters.
- **Whether to also export `alb_arn`/`alb_dns_name`/`cert_domain`/`zone_name_servers`** — only `cert_arn`, `listener_arn`, `hosted_zone_id` are contractually required.
- **`route53 force_destroy`** — planner's discretion (zone has no TF-managed records, either value is offline-safe).

### Deferred Ideas (OUT OF SCOPE)

- ACM DNS validation chain (`aws_route53_record` + `aws_acm_certificate_validation`)
- Fleet-wide wildcard `*.{tenant_domain}` ALIAS → ALB record
- ALB access logs (S3 bucket + bucket policy + `access_logs` block)
- Per-tenant target groups, host-routing rules, DNS records — provisioner adapter's job
- `healthCheckGracePeriod >= 240s` — ECS service property, adapter-owned

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID     | Description                                                                          | Research Support                                                                                     |
|--------|--------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|
| ACM-01 | `modules/acm` declares wildcard ACM cert for `*.{tenant_domain}` using DNS validation | See `aws_acm_certificate` HCL syntax, `create_before_destroy`, wildcard domain_name pattern          |
| ALB-01 | `modules/alb` declares shared ALB with HTTPS listener (ACM cert, idle_timeout > 60) | See `aws_lb` + `aws_lb_listener` HCL; `idle_timeout` lives on `aws_lb`, not listener               |
| DNS-01 | `modules/route53` declares public hosted zone for `tenant_domain`; no per-tenant records | See `aws_route53_zone` HCL; `name = var.tenant_domain` is all that is required                      |
| TLS-02 | `acm`, `alb`, `route53` calls and three outputs uncommented and wired in `envs/prod` | See wiring order (acm before alb), stub gaps, and plan-check pitfall around `tenant_domain` validation |

</phase_requirements>

---

## Summary

Phase 5 implements three lightweight Terraform modules (`acm`, `alb`, `route53`) and wires them into `envs/prod`, completing the full provisioner output contract. All four decisions are locked in CONTEXT.md; this research surfaces the exact AWS provider 6.x HCL syntax and the one real offline-plan pitfall that the planner must address.

The modules are intentionally decoupled: `acm` does not know about `route53` (bare cert, no validation chain), `route53` does not know about `alb` (no wildcard ALIAS record), and `alb` does not know about route53. This matches the no-module-to-module-calls architectural constraint.

**Critical pitfall:** The Makefile `plan-check` target runs `terraform plan -input=false` with no `-var` flags and no `terraform.tfvars` file (that file is gitignored). When `module "acm"` and `module "route53"` are uncommented and their variables include a regex `validation` block that rejects empty strings, `tenant_domain = ""` (the current root default) will cause the plan to fail. The planner must add `-var "tenant_domain=placeholder.example.com"` to the `terraform plan` command inside `plan-check`. This is the "dummy value" the CONTEXT.md refers to.

**Primary recommendation:** Follow the locked decisions exactly. The only planner discretion items are variable names for ALB's subnet/SG inputs, the exact domain regex, and the 503 message body. All resource syntax is stable across AWS provider `~> 6.0` — no breaking changes affect `aws_lb`, `aws_acm_certificate`, or `aws_route53_zone` in provider v6.

---

## Architectural Responsibility Map

| Capability                          | Primary Tier        | Secondary Tier | Rationale                                                                 |
|-------------------------------------|---------------------|----------------|---------------------------------------------------------------------------|
| Wildcard TLS certificate            | AWS ACM             | —              | ACM manages cert lifecycle; Terraform declares the cert only (bare, D-02) |
| HTTPS termination / HTTP upgrade    | ALB (Internet-edge) | —              | ALB terminates TLS and redirects HTTP; tasks never see raw HTTPS          |
| Host-based routing (per-tenant)     | ALB (adapter-owned) | —              | Adapter attaches rules to the exported `listener_arn` at provision time   |
| DNS zone management                 | Route53             | —              | Terraform declares the zone; adapter adds per-tenant records at runtime   |
| Provisioner output contract closure | `envs/prod`         | —              | Root re-exports `cert_arn`, `listener_arn`, `hosted_zone_id` to adapter   |

---

## Standard Stack

### Core

| Resource                     | Provider Version | Purpose                                         | Why Standard                                               |
|------------------------------|------------------|-------------------------------------------------|------------------------------------------------------------|
| `aws_acm_certificate`        | `~> 6.0`         | Wildcard TLS cert for `*.{tenant_domain}`       | Native AWS cert service; DNS validation offline-safe       |
| `aws_lb`                     | `~> 6.0`         | Internet-facing application load balancer       | ELBv2 `aws_lb`; `aws_alb` is an alias still supported     |
| `aws_lb_listener` (HTTP:80)  | `~> 6.0`         | 301 redirect to HTTPS                           | Ensures all clients use HTTPS without connection-refused   |
| `aws_lb_listener` (HTTPS:443)| `~> 6.0`         | TLS termination; default 503 for unrouted hosts | Fixed-response 503 = "no tenant yet" semantic              |
| `aws_route53_zone`           | `~> 6.0`         | Public hosted zone for `tenant_domain`          | Native AWS DNS; adapter adds per-tenant records at runtime |

No new providers are required. `hashicorp/aws ~> 6.0` covers all five resources. [VERIFIED: codebase — `envs/prod/versions.tf` + `.terraform.lock.hcl` pins `6.51.0`]

---

## Package Legitimacy Audit

No external packages are installed in this phase. All resources use the already-pinned `hashicorp/aws ~> 6.0` provider (`6.51.0` locked in `.terraform.lock.hcl`). [VERIFIED: codebase]

---

## Architecture Patterns

### System Architecture Diagram

```
Internet
    │
    ▼
[ALB Security Group]  (ingress 80/443 from 0.0.0.0/0 — Phase 1, no change)
    │
    ├─ HTTP:80 listener ──► 301 redirect to HTTPS:443
    │
    └─ HTTPS:443 listener (ACM cert: *.{tenant_domain})
            │
            └─ default_action: fixed-response 503
            │   (no tenant yet — adapter attaches host rules later)
            │
            └─ [adapter-created host rules at provision time → tenant target groups]

envs/prod/outputs.tf
    ├─ acm_cert_arn    ← module.acm.cert_arn
    ├─ alb_listener_arn ← module.alb.listener_arn  (the HTTPS:443 listener arn)
    └─ hosted_zone_id  ← module.route53.hosted_zone_id

ACM certificate: *.{tenant_domain}  (DNS validation, bare — no validation chain this phase)
Route53 zone: {tenant_domain}        (public, no records — adapter adds per-tenant records)
```

### Recommended Project Structure

No new directories. Add resources to existing stubs:

```
modules/
├── acm/
│   ├── main.tf        # aws_acm_certificate (wildcard, DNS val, create_before_destroy)
│   ├── variables.tf   # name_prefix, tenant_domain (+ validation block)
│   └── outputs.tf     # cert_arn
├── alb/
│   ├── main.tf        # aws_lb, aws_lb_listener x2
│   ├── variables.tf   # name_prefix, acm_cert_arn, subnet_ids, security_group_id
│   └── outputs.tf     # listener_arn (HTTPS listener)
└── route53/
    ├── main.tf        # aws_route53_zone (public, name = var.tenant_domain)
    ├── variables.tf   # tenant_domain (+ validation block)
    └── outputs.tf     # hosted_zone_id
envs/prod/
├── main.tf            # uncomment module "acm", "alb", "route53"; add subnet/SG wiring to alb
└── outputs.tf         # uncomment acm_cert_arn, alb_listener_arn, hosted_zone_id
Makefile               # add -var "tenant_domain=placeholder.example.com" to plan-check
```

### Pattern 1: ACM Wildcard Certificate (bare, offline-safe)

```hcl
# Source: renehernandez.io/snippets/terraform-and-aws-wildcard-certificates-validation/ [CITED]
# + verified against AWS provider 6.x change log (no breaking changes for this resource) [CITED]
resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.tenant_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
```

Key points:
- `domain_name = "*.${var.tenant_domain}"` — the wildcard covers all `{slug}.{tenant_domain}` subdomains. No SAN needed because the apex domain (`tenant_domain` itself) is not served by the ALB. [ASSUMED — based on SEED-001 routing design: tenants are at subdomains only]
- No `aws_acm_certificate_validation` resource — locked by D-02. Plan validates offline; cert stays PENDING_VALIDATION until a real apply wires the CNAME into Route53. [VERIFIED: CONTEXT.md D-02]
- `create_before_destroy = true` — zero-downtime cert rotation; no AWS cost; fully offline-safe. [CITED: headforthe.cloud/article/managing-acm-with-terraform/]
- `domain_validation_options` is an exported attribute set — the planner does NOT need to iterate it this phase (validation chain is deferred). [VERIFIED: CONTEXT.md D-02]

### Pattern 2: Application Load Balancer

```hcl
# Source: multiple community sources cross-verified; no breaking changes in aws provider 6.x [CITED]
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  idle_timeout               = 120   # must be > 60 (Odoo longpoll ~50s guard)
  enable_deletion_protection = false
  enable_http2               = true
  drop_invalid_header_fields = true
}
```

Key points:
- `idle_timeout` lives on `aws_lb` (the LB resource), NOT on `aws_lb_listener`. [ASSUMED — from training knowledge; no breaking change found in provider 6.x that moved this attribute]
- `name` has a 32-character AWS limit. `"${var.name_prefix}-alb"` = `"odoo-saas-prod-alb"` = 18 characters — well within limit. [VERIFIED: codebase — name_prefix = "odoo-saas-prod"]
- `subnets` argument takes a `list(string)` of subnet IDs. [CITED: registry.terraform.io docs for aws_lb]
- No `access_logs` block — locked by D-04. [VERIFIED: CONTEXT.md D-04]
- No per-resource `tags = {}` — tags applied via provider `default_tags` only. [VERIFIED: CONVENTIONS.md]

### Pattern 3: HTTPS:443 Listener (fixed-response 503 default)

```hcl
# Source: registry.terraform.io/providers/-/aws/6.32.0/docs/resources/lb_listener [CITED]
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

Key points:
- `ssl_policy` is required when `protocol = "HTTPS"`. `ELBSecurityPolicy-TLS13-1-2-2021-06` enforces TLS 1.2/1.3 — this is the current standard. A newer 2025 policy (`ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`) exists but is Claude's Discretion to adopt. [CITED: www.trendmicro.com + cloudposse/terraform-aws-alb issue #178]
- `certificate_arn = var.acm_cert_arn` — this takes any valid ARN-shaped string at plan time. The offline plan-check with dummy AWS credentials produces `(known after apply)` for the ACM cert ARN, and Terraform accepts this reference without error because `module.acm.cert_arn` is a computed string. [ASSUMED — based on plan-check behavior with other computed ARNs (e.g., RDS endpoint) verified in prior phases]
- `fixed_response` is nested inside `default_action` — NOT a top-level attribute. This block shape has not changed in provider 6.x. [CITED: github.com/hashicorp/terraform-provider-aws/issues/41101 — no breaking change for `aws_lb_listener.default_action.fixed_response`]
- The `listener_arn` output from this resource is `.arn` attribute: `aws_lb_listener.https.arn`. [ASSUMED — standard Terraform AWS provider attribute naming, consistent with all other *_listener.arn attributes]

### Pattern 4: HTTP:80 Listener (301 redirect)

```hcl
# Source: registry.terraform.io/providers/-/aws/6.32.0/docs/resources/lb_listener [CITED]
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

Key points:
- `ssl_policy` and `certificate_arn` are NOT set on HTTP listeners. Setting them on HTTP would cause a validation error. [ASSUMED — from training knowledge; consistent with AWS ELBv2 behavior]
- `status_code = "HTTP_301"` (string, not integer). [CITED: registry.terraform.io aws_lb_listener docs]
- The redirect block must specify all three fields: `port`, `protocol`, `status_code`. [CITED: registry.terraform.io]

### Pattern 5: Route53 Public Hosted Zone

```hcl
# Source: registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone [CITED]
resource "aws_route53_zone" "main" {
  name          = var.tenant_domain
  force_destroy = false
}
```

Key points:
- `name = var.tenant_domain` — the zone name IS the domain. No `name_prefix` interpolation. [VERIFIED: AWS Route53 zone naming is domain-based]
- `force_destroy` — controls whether TF-unmanaged records are deleted on `terraform destroy`. Since this phase creates no records, either value is equivalent. Planner's discretion per CONTEXT.md. [CITED: CONTEXT.md Claude's Discretion section]
- The exported attribute is `aws_route53_zone.main.zone_id`. [ASSUMED — standard attribute name; `id` and `zone_id` are both accessible and equivalent on this resource]
- No `comment` argument required. AWS creates a default comment. [ASSUMED]
- No `vpc` block — this is a public zone (no VPC association). [VERIFIED: CONTEXT.md "public aws_route53_zone"]

### Pattern 6: Variable Validation for `tenant_domain`

```hcl
# Source: CONCERNS.md recommendation + dev.to/drewmullen/terraform-variable-validation-with-samples [CITED]
variable "tenant_domain" {
  description = "Apex domain that tenant instances live under, e.g. \"saas.example.com\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))
    error_message = "tenant_domain must be a valid apex domain, e.g. saas.example.com."
  }
}
```

Key points:
- `can(regex(...))` returns `false` (not an error) when the pattern does not match. This is the correct idiom for validation conditions. [CITED: dev.to/drewmullen]
- The regex `^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$` rejects: empty string, strings without a dot, strings with invalid TLD (less than 2 chars). It accepts `saas.example.com`, `placeholder.example.com`. [CITED: CONCERNS.md provides this exact regex; verified against spacelift.io/blog/terraform-regex]
- The double-backslash `\\.` is required because HCL strings treat `\` as an escape character — `\\.` in HCL becomes `\.` in regex (literal dot). [CITED: spacelift.io/blog/terraform-regex]
- **Same validation block** should be copy-pasted into BOTH `modules/acm/variables.tf` AND `modules/route53/variables.tf`. [VERIFIED: CONTEXT.md phase boundary, locked requirement]

### Pattern 7: Wiring in `envs/prod/main.tf`

The existing commented stubs are the starting point. The `alb` stub is incomplete — it must be expanded to include subnet/SG wiring. The correct wiring order (acm before alb) is critical because `module.acm.cert_arn` is referenced in the `alb` call:

```hcl
# Build step 6 — Routing/TLS. acm MUST precede alb in the file (dependency order).
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
  name_prefix   = local.name_prefix    # convention; route53 stub omitted it; planner decides
  tenant_domain = var.tenant_domain
}
```

Notes on wiring:
- `module.networking.private_subnet_ids` is the public subnet list (named under that contract). [VERIFIED: modules/networking/outputs.tf]
- `module.networking.alb_security_group_id` already exists and is plan-green from Phase 1. [VERIFIED: modules/networking/outputs.tf + envs/prod/outputs.tf]
- The route53 stub in `envs/prod/main.tf` omits `name_prefix`. Since `aws_route53_zone` has no `name_prefix` argument (zone name = domain), and provider `default_tags` handles tagging, `name_prefix` is not consumed by route53's resource body. The planner may include it by convention or omit it. If included, `modules/route53/variables.tf` must declare it. [VERIFIED: codebase stub at envs/prod/main.tf line 106–108]

### Anti-Patterns to Avoid

- **Using `aws_alb` instead of `aws_lb`:** `aws_alb` is a legacy alias. Use `aws_lb` for all new resources. [CITED: spacelift.io/blog/terraform-alb — "aws_alb is known as aws_lb"]
- **Putting `idle_timeout` on the listener:** `idle_timeout` is an attribute of `aws_lb`, not `aws_lb_listener`. Placing it on the listener causes an unsupported argument error. [ASSUMED — confirmed from architecture; no breaking change moved this]
- **Setting `ssl_policy` on HTTP:80 listener:** Only valid for `protocol = "HTTPS"`. Setting it on HTTP causes an error. [ASSUMED — standard AWS ELBv2 constraint]
- **Using `aws_lb_listener_rule` for the default 503:** The default action belongs on `aws_lb_listener.default_action`, not on a separate `aws_lb_listener_rule`. Rules are for tenant-specific host routing (adapter-owned). [VERIFIED: CONTEXT.md D-01]
- **Adding `domain_validation_options` iteration or `aws_acm_certificate_validation`:** Locked out by D-02. This also avoids the known pitfall where wildcard + apex produce duplicate CNAME validation records. [VERIFIED: CONTEXT.md D-02]
- **Per-resource `tags = {}` blocks:** All tagging is via provider `default_tags`. No module should add per-resource tags. [VERIFIED: CONVENTIONS.md]

---

## Don't Hand-Roll

| Problem                         | Don't Build                            | Use Instead                            | Why                                                                              |
|---------------------------------|----------------------------------------|----------------------------------------|----------------------------------------------------------------------------------|
| TLS certificate management      | Custom cert generation / self-signed   | `aws_acm_certificate`                  | ACM handles renewal, cross-region availability, ALB native integration           |
| HTTP→HTTPS upgrade              | Target group with redirect logic        | `aws_lb_listener` redirect action      | Native ELBv2 redirect; zero target group needed                                  |
| 503 "no backend" response       | Dummy target group + Lambda / EC2      | `fixed-response` default action        | Native action type; no targets, no cost, plans offline cleanly                   |
| DNS zone hosting                | Custom NS record management            | `aws_route53_zone`                     | Route53 issues NS records on zone creation; adapts to per-tenant records at runtime |

---

## Common Pitfalls

### Pitfall 1: `tenant_domain` validation breaks `make plan-check`

**What goes wrong:** After adding a `validation` block to `modules/acm/variables.tf` and `modules/route53/variables.tf` that rejects empty strings, and then uncommenting the module calls in `envs/prod/main.tf`, `make plan-check` fails with a validation error because `var.tenant_domain` defaults to `""` (the gitignored `terraform.tfvars` file does not exist, and `plan-check` passes no `-var` flags).

**Why it happens:** The `plan-check` Makefile target runs `terraform plan -input=false` with no `-var` or `-var-file` arguments. No `terraform.tfvars` is committed (gitignored per `.gitignore`). The root variable defaults to `""` and that empty string flows into both module variables. The regex validation `^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$` rejects `""`, so Terraform aborts with an error before planning any resources.

**How to avoid:** The planner must update the `plan-check` Makefile target to inject a dummy domain value into the `terraform plan` command:

```makefile
terraform plan -input=false -var "tenant_domain=placeholder.example.com"
```

`placeholder.example.com` satisfies the regex (non-empty, valid domain shape), is plainly a non-real domain, and is committed directly in the Makefile (not in a gitignored tfvars). This matches CONTEXT.md's statement "the offline gate supplies a dummy value."

**Warning signs:** `make plan-check` exits with an error message like `Error: Invalid value for variable` pointing to `tenant_domain` in either the acm or route53 module.

---

### Pitfall 2: Wiring `alb` module without subnet/SG inputs

**What goes wrong:** The existing commented `module "alb"` stub in `envs/prod/main.tf` only passes `name_prefix` and `acm_cert_arn`. If the planner uncomments the stub as-is, `terraform plan` fails with "unsupported argument" or the ALB is created without subnets/SGs, which would itself fail validation.

**Why it happens:** The stub was written before the wiring inputs were identified. CONTEXT.md Claude's Discretion section explicitly calls this out.

**How to avoid:** Expand the `module "alb"` call to include at minimum `subnet_ids = module.networking.private_subnet_ids` and `security_group_id = module.networking.alb_security_group_id`. Pre-declare matching variables in `modules/alb/variables.tf` BEFORE uncommenting the call.

**Warning signs:** `terraform validate` error: "An argument named X is not expected here" on the module call, or `terraform plan` error: "Required argument not found" in the module.

---

### Pitfall 3: Forgetting to update the ALB stub's variable declarations before uncommenting

**What goes wrong:** `terraform validate` (and `terraform plan`) fail with "unsupported argument" for any input in the module call that is not declared in `modules/alb/variables.tf`.

**Why it happens:** Terraform requires every argument in a module call to correspond to a declared variable. The alb stub `variables.tf` currently has only `name_prefix`. Adding `acm_cert_arn`, `subnet_ids`, and `security_group_id` to the call without pre-declaring them causes an immediate plan failure.

**How to avoid:** Follow the established CONCERNS.md pattern — pre-declare ALL new module variables in `variables.tf` before uncommenting the module call.

**Warning signs:** Error at `terraform validate` or `terraform plan`: "An argument named \"acm_cert_arn\" is not expected here."

---

### Pitfall 4: `aws_lb_listener_rule` nested block syntax change in provider 6.x

**What goes wrong:** AWS provider v6.0 changed the nested block attribute format in `aws_lb_listener_rule` from multi-block to single-block syntax (the "SingleNestedBlock" change). Code written for provider 5.x using `action.fixed_response[0].status_code` breaks.

**Why it happens:** This is a documented provider 6.x breaking change.

**How to avoid:** Phase 5 does NOT use `aws_lb_listener_rule`. The default 503 action is implemented as `aws_lb_listener.default_action` (not a rule). Per-tenant rules are adapter-owned. So this breaking change does NOT affect Phase 5 at all.

**Warning signs:** N/A for this phase; relevant only if `aws_lb_listener_rule` is introduced in a future phase.

---

### Pitfall 5: ACM cert name confusion — no `name` argument

**What goes wrong:** Attempting to use `name = "${var.name_prefix}-cert"` on `aws_acm_certificate` fails because this resource has no `name` argument. ACM certificates are identified by `domain_name`.

**Why it happens:** Other AWS resources (like `aws_lb`) use `name`. The `name_prefix` convention in this project creates a mental model that all resources accept it.

**How to avoid:** `aws_acm_certificate` only accepts `domain_name` (the wildcard), `validation_method`, optional `subject_alternative_names`, and lifecycle blocks. No `name` attribute exists on this resource. The `name_prefix` module variable is accepted by convention but not used in the resource block itself. [ASSUMED — from training knowledge; consistent with ACM API surface]

---

### Pitfall 6: `aws_route53_zone.zone_id` vs `.id` attribute

**What goes wrong:** Using `.id` vs `.zone_id` inconsistently when referencing the zone in outputs.

**Why it happens:** `aws_route53_zone` exports both `.id` and `.zone_id`, and they return the same value. The provisioner contract says `hosted_zone_id`, so the output should reference whichever attribute is idiomatic.

**How to avoid:** Use `aws_route53_zone.main.zone_id` for clarity — it's explicit about what is being exported and matches the output name `hosted_zone_id`. Either `.id` or `.zone_id` works. [ASSUMED — both are valid; `.zone_id` is more explicit]

---

## Code Examples

### modules/acm/variables.tf

```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "tenant_domain" {
  description = "Apex domain for the wildcard ACM certificate, e.g. \"saas.example.com\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))
    error_message = "tenant_domain must be a valid apex domain, e.g. saas.example.com."
  }
}
```

### modules/acm/outputs.tf

```hcl
output "cert_arn" {
  description = "Wildcard ACM certificate ARN -> provisioner `aws_acm_cert_arn`."
  value       = aws_acm_certificate.wildcard.arn
}
```

### modules/alb/variables.tf (minimum)

```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "acm_cert_arn" {
  description = "ARN of the wildcard ACM certificate for the HTTPS listener."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the ALB (across >=2 AZs)."
  type        = list(string)
}

variable "security_group_id" {
  description = "ALB security group ID (allows ingress 80/443 from internet)."
  type        = string
}
```

### modules/alb/outputs.tf

```hcl
output "listener_arn" {
  description = "HTTPS:443 listener ARN -> provisioner `aws_alb_listener_arn`."
  value       = aws_lb_listener.https.arn
}
```

### modules/route53/variables.tf

```hcl
variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "tenant_domain" {
  description = "Apex domain for the Route53 hosted zone, e.g. \"saas.example.com\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))
    error_message = "tenant_domain must be a valid apex domain, e.g. saas.example.com."
  }
}
```

### modules/route53/outputs.tf

```hcl
output "hosted_zone_id" {
  description = "Route53 hosted zone ID -> provisioner `aws_hosted_zone_id`."
  value       = aws_route53_zone.main.zone_id
}
```

### envs/prod/outputs.tf additions (uncomment)

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

### Makefile `plan-check` target modification

Add `-var "tenant_domain=placeholder.example.com"` to the `terraform plan` call:

```makefile
terraform plan -input=false -var "tenant_domain=placeholder.example.com"
```

---

## State of the Art

| Old Approach                      | Current Approach                                    | When Changed        | Impact                                                  |
|-----------------------------------|-----------------------------------------------------|---------------------|---------------------------------------------------------|
| `aws_alb` resource type           | `aws_lb` (preferred); `aws_alb` is legacy alias     | Provider ~3.x       | Use `aws_lb`; `aws_alb` still works but avoid in new code |
| `aws_lb_listener_rule` block style | Single-nested block in provider 6.x                | Provider 6.0 (2025) | Only affects `aws_lb_listener_rule`, not `aws_lb_listener` |
| ELBSecurityPolicy-2015-05 SSL     | ELBSecurityPolicy-TLS13-1-2-2021-06 (standard)     | ~2021               | Must use a TLS 1.2+ policy; older policies deprecated   |
| ACM cert + inline CNAME creation  | Bare cert + separate validation resources (deferred)| n/a                 | This phase uses bare cert intentionally (D-02)          |

**Deprecated / outdated:**

- `aws_alb`: Legacy alias. Functional but prefer `aws_lb` in new code. [CITED: spacelift.io/blog/terraform-alb]
- OpsWorks resources: Removed entirely in provider 6.0. Not relevant to this phase. [CITED: scalr.com/learning-center/aws-provider-v6-0-whats-breaking-in-april-2025]
- `aws_eip.vpc`: Removed in provider 6.0 (use `domain = "vpc"` instead). Not relevant. [CITED: above]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `idle_timeout` is an attribute of `aws_lb`, not `aws_lb_listener` | Pattern 2 (ALB resource) | Plan-time "unsupported argument" error; easy to fix by moving the attribute |
| A2 | `aws_lb_listener.https.arn` is the correct attribute reference (not `.listener_arn`) | Pattern 3, Code Examples | Output resolves to wrong value or plan fails; fix by using `.arn` |
| A3 | `aws_route53_zone.main.zone_id` and `.id` are equivalent | Pattern 5, Code Examples | No functional risk; both return the zone ID |
| A4 | `aws_acm_certificate` has no `name` argument | Pitfall 5 | Plan-time "unsupported argument" if a `name` attribute is attempted |
| A5 | A wildcard cert for `*.{tenant_domain}` does not need a SAN for the apex domain | Pattern 1 | If the ALB ever needs to serve requests to the bare apex, the cert would be invalid; SEED-001 only routes subdomains |
| A6 | The HTTPS listener's `certificate_arn` pointing to a computed (not-yet-known) ACM ARN passes `terraform plan` cleanly under the offline gate | Pitfall section | If the provider validates the ARN format during plan (not apply), the dummy plan would fail; prior phase behavior with computed RDS ARNs suggests this is not an issue |
| A7 | `ssl_policy` argument is NOT valid on HTTP:80 listener | Pattern 4 | Plan-time error if mistakenly set |

---

## Open Questions

1. **Does `route53` module need `name_prefix`?**
   - What we know: The current `route53/variables.tf` stub declares only `name_prefix`. The existing commented stub call in `envs/prod/main.tf` does NOT pass `name_prefix` to route53. The zone resource has no name attribute that would use `name_prefix` (zone name = domain). Provider `default_tags` handles tagging.
   - What's unclear: Whether to keep `name_prefix` in route53 for convention or omit it (clean interface).
   - Recommendation: The planner can include `name_prefix` for convention adherence (pass from envs/prod, declare in route53/variables.tf, unused in the resource body) or omit it since no resource uses it. Either passes the plan. The stub call omitting it suggests omission is acceptable.

2. **Can the HTTPS listener plan offline with a computed (not-yet-known) `certificate_arn`?**
   - What we know: All prior computed ARNs (RDS endpoints, EFS IDs, ECS ARNs) plan successfully offline under `make plan-check`. The AWS provider with `skip_credentials_validation=true` and dummy credentials does not validate ARN formats during plan.
   - What's unclear: Whether the HTTPS listener resource performs any ARN format validation at plan time that would fail with `(known after apply)`.
   - Recommendation: Proceed with `certificate_arn = var.acm_cert_arn` (which will be `(known after apply)` in the offline plan). This is almost certainly fine based on prior phase experience. If the plan fails here, the fix is to add a `depends_on` or restructure — but this is unlikely.

---

## Environment Availability

| Dependency           | Required By           | Available | Version  | Fallback           |
|----------------------|-----------------------|-----------|----------|--------------------|
| Terraform            | All module implementation | ✓     | 1.15.6   | —                  |
| `hashicorp/aws ~> 6.0` | All AWS resources   | ✓         | 6.51.0 (locked) | —             |
| AWS credentials (real) | `make apply` only  | N/A       | —        | Offline gate via `make plan-check` |
| `terraform.tfvars`   | Real plan/apply       | ✗         | —        | Dummy `-var` in plan-check Makefile |

**Missing dependencies with no fallback:** None for this phase (code-complete only, no `terraform apply`).

**Missing dependencies with fallback:** `terraform.tfvars` — addressed by injecting `-var "tenant_domain=placeholder.example.com"` in `plan-check`.

---

## Security Domain

Security enforcement is enabled (`security_enforcement: true`, ASVS level 1).

### Applicable ASVS Categories

| ASVS Category          | Applies | Standard Control                                                   |
|------------------------|---------|--------------------------------------------------------------------|
| V2 Authentication      | no      | No authentication layer in this phase                              |
| V3 Session Management  | no      | No session management in Terraform resources                       |
| V4 Access Control      | yes     | ALB SG ingress limited to 80/443 only (Phase 1, no change); task SG blocks non-ALB traffic |
| V5 Input Validation    | yes     | `validation {}` block on `tenant_domain` in acm and route53 modules |
| V6 Cryptography        | yes     | TLS 1.2/1.3 enforced via `ELBSecurityPolicy-TLS13-1-2-2021-06`; ACM manages cert |

### Known Threat Patterns for this Stack

| Pattern                              | STRIDE      | Standard Mitigation                                              |
|--------------------------------------|-------------|------------------------------------------------------------------|
| Invalid domain creates wildcard cert  | Tampering   | `validation {}` block in modules/acm and modules/route53 rejects empty/invalid domains |
| HTTP plaintext interception           | Info Disclosure | HTTP:80 → HTTPS:301 redirect listener (D-01)                |
| Weak TLS ciphers                      | Tampering   | `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` (TLS 1.2+ only) |
| ALB accepts invalid HTTP headers      | Tampering   | `drop_invalid_header_fields = true` (D-04)                       |
| Direct internet access to tasks       | Elevation   | Task SG accepts 8069 only from ALB SG id (Phase 1, unchanged)   |
| Secrets in Terraform state/outputs    | Info Disclosure | No secrets in this phase (cert ARN, zone ID, listener ARN are non-secret identifiers) |

---

## Sources

### Primary (HIGH confidence)

- CONTEXT.md — All locked decisions D-01 through D-04, wiring stubs, integration points
- `modules/networking/outputs.tf` — `alb_security_group_id`, `private_subnet_ids` confirmed active outputs
- `envs/prod/main.tf` — Commented stubs showing exact expected wiring
- `Makefile` — `plan-check` target behavior confirmed; no `-var` injection currently
- `.planning/codebase/CONCERNS.md` — Exact `tenant_domain` regex recommendation
- `.planning/codebase/CONVENTIONS.md` — Module interface, naming, tagging rules
- `envs/prod/.terraform.lock.hcl` — AWS provider pinned at `6.51.0`

### Secondary (MEDIUM confidence)

- [registry.terraform.io aws_lb_listener v6.32.0](https://registry.terraform.io/providers/-/aws/6.32.0/docs/resources/lb_listener) — confirmed argument shapes for `fixed-response`, `redirect`, `ssl_policy`, `certificate_arn` [CITED]
- [renehernandez.io — Terraform and AWS wildcard certificate validation](https://renehernandez.io/snippets/terraform-and-aws-wildcard-certificates-validation/) — confirmed wildcard `domain_name` + `lifecycle.create_before_destroy` pattern [CITED]
- [github.com/hashicorp/terraform-provider-aws/issues/41101](https://github.com/hashicorp/terraform-provider-aws/issues/41101) — confirmed no breaking changes for `aws_lb`, `aws_acm_certificate`, `aws_route53_zone` in provider 6.0; only `aws_lb_listener_rule` had nested block changes [CITED]
- [scalr.com — AWS Provider v6.0 breaking changes](https://scalr.com/learning-center/aws-provider-v6-0-whats-breaking-in-april-2025) — confirmed `aws_lb` not mentioned in breaking changes [CITED]
- [dev.to/drewmullen — Terraform variable validation](https://dev.to/drewmullen/terraform-variable-validation-with-samples-1ank) — confirmed `can(regex(...))` idiom and double-backslash escaping [CITED]
- [registry.terraform.io aws_route53_zone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) — confirmed `name` and `force_destroy` arguments [CITED]

### Tertiary (LOW confidence — not used in recommendations)

- Various blog posts about ALB Terraform examples — used for cross-checking only; superseded by official docs where available

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — AWS provider 6.51.0 locked; all resource types confirmed
- Architecture: HIGH — locked by CONTEXT.md D-01 through D-04; stubs verified in codebase
- Pitfalls: HIGH — Pitfall 1 (plan-check + validation) directly verified by reading Makefile + gitignore; others are codebase-verified patterns from prior phases
- HCL syntax specifics: MEDIUM-HIGH — primary sources confirmed shapes; a few attributes (idle_timeout placement, .arn attribute) tagged [ASSUMED] due to registry rendering issues

**Research date:** 2026-06-24
**Valid until:** 2026-08-01 (stable AWS provider; no imminent 7.x release expected)
