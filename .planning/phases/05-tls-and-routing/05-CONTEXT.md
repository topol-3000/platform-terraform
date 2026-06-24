# Phase 5: TLS and routing - Context

**Gathered:** 2026-06-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `modules/acm`, `modules/alb`, and `modules/route53` and wire all three into `envs/prod`, keeping the offline `make plan-check` gate green and completing the **full provisioner output contract** (`acm_cert_arn`, `alb_listener_arn`, `hosted_zone_id` — the last three commented outputs in `envs/prod/outputs.tf`). This is the final phase of milestone v1.1.

Locked by ROADMAP Phase 5 success criteria + carried-forward conventions (NOT gray areas — do NOT re-discuss):
- **acm:** a **wildcard** `aws_acm_certificate` for `*.{tenant_domain}` using `validation_method = "DNS"`; `tenant_domain` guarded by a regex `validation` block (no empty-string default silently creating an invalid cert); module exports `cert_arn`.
- **route53:** a **public** `aws_route53_zone` for `tenant_domain` with the same `tenant_domain` `validation` block; module exports `hosted_zone_id`; **no per-tenant DNS records** created by Terraform.
- **alb:** a shared, internet-facing `aws_lb` (application) with an **HTTPS:443 listener** referencing `var.acm_cert_arn` and `idle_timeout > 60` (Odoo longpoll ~50s guard); module exports `listener_arn`; **no per-tenant target groups or host rules** created by Terraform.
- **Wiring order:** `acm` is called **before** `alb` so `module.acm.cert_arn` resolves into `alb`'s `acm_cert_arn`. Uncomment the `acm`/`alb`/`route53` module calls in `envs/prod/main.tf` and the `acm_cert_arn` / `alb_listener_arn` / `hosted_zone_id` outputs in `envs/prod/outputs.tf`.
- **Pre-declare every new module variable before uncommenting its call** (CONCERNS.md): `tenant_domain` in `modules/acm/variables.tf` and `modules/route53/variables.tf`; `acm_cert_arn` in `modules/alb/variables.tf`; plus the wiring inputs the ALB needs (see Claude's Discretion). An undeclared argument fails the plan with "unsupported argument".
- **Verification is code-complete only:** `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` via the offline dummy-AWS `make plan-check` gate. **No `terraform apply`, no AWS spend, no live data sources, no `skip_*` provider flags.**

Covers requirements ACM-01, ALB-01, DNS-01, TLS-02. Per-tenant resources (target groups, host-routing rules, DNS records) are explicitly out of scope — adapter-owned at runtime.

</domain>

<decisions>
## Implementation Decisions

### ALB listener topology (the 443 listener is locked; what surrounds it)
- **D-01:** Build **two** listeners. (a) An **HTTP:80 listener** whose sole action is a **301 redirect to HTTPS** (`port=443`, `protocol=HTTPS`, `status_code=HTTP_301`). (b) The locked **HTTPS:443 listener** (ACM cert, `idle_timeout > 60`) whose **`default_action` is a `fixed-response` 503** ("no tenant" / service-unavailable) for any request that matches no host rule — because per-tenant target groups and host rules are adapter-created, so the listener has no real backend yet but still requires a `default_action` to plan/apply. The networking ALB SG already allows ingress on both 80 and 443, so no SG change is needed. Rejected: 443-only (plain-HTTP clients get connection-refused instead of an upgrade); 404 default (503 more accurately signals "no tenant provisioned yet" than "not found").

### ACM DNS validation depth (verification is code-complete only)
- **D-02:** Declare the **bare `aws_acm_certificate`** with `validation_method = "DNS"` **only** — do **NOT** wire the validation chain (no `aws_route53_record` for `domain_validation_options`, no `aws_acm_certificate_validation` resource). Rationale: verification is plan-only/offline, so the validation resource would do nothing offline and only adds apply-time coupling; keeping the cert bare keeps `acm` and `route53` **decoupled** (matches the stub wiring where `module "acm"` takes `tenant_domain` but **not** a zone id). DNS validation completes at real apply-time later (out of scope this milestone). Add `lifecycle { create_before_destroy = true }` on the cert (standard ACM practice; free, offline-safe). Rejected: full validation chain (couples `acm → route53`, adds an apply-only no-op resource).

### Fleet-wide DNS records
- **D-03:** The `route53` module declares **only the hosted zone** (exports `hosted_zone_id`) — **no records of any kind**, not even a fleet-wide wildcard `*.{tenant_domain}` ALIAS. Keeps `route53` fully **decoupled** from `alb` (no need to thread the ALB `dns_name`/`zone_id` into route53), matches the SEED-001 route53 stub note ("per-tenant records created by the adapter at provision time"), and satisfies criteria #2 literally. Rejected: wildcard `*.{tenant_domain}` ALIAS → ALB (would couple `route53 → alb` and pull DNS ownership away from the adapter; revisit only if the provisioner design later wants fleet-wide DNS in the baseline — see Deferred Ideas).

### ALB cost / hardening toggles (cost-lean MVP pattern)
- **D-04:** Keep the ALB **lean**, consistent with the Phase 3/4 cost-lean posture (proxy-off, backups-off, AWS-managed keys): **no access logs** (no S3 bucket + bucket policy — zero extra resources/cost, avoids an apply-time bucket-policy dependency), `enable_deletion_protection = false`. Keep the **free** hardening on: `enable_http2 = true` (default) and `drop_invalid_header_fields = true`. ALB access logs are flagged as a **deferred hardening item** (see Deferred Ideas), not a permanent stance. Rejected: provision an access-log S3 bucket now (adds resources/cost + bucket-policy coupling before it's prioritized).

### Claude's Discretion
- **ALB wiring inputs** — the current `module "alb"` stub call passes only `name_prefix` + `acm_cert_arn`; the planner must additionally thread the **public subnets** (`module.networking.private_subnet_ids` — the public-subnet set, exported under that contract name) and the **ALB security group** (`module.networking.alb_security_group_id`) into the module, and declare matching variables (`subnet_ids`, `security_group_id`/`security_group_ids`, and `vpc_id` if a target-group/listener needs it). `internal = false` (internet-facing), `load_balancer_type = "application"`. Variable names / resource labels / `for_each`-vs-list subnet style are the planner's discretion following established conventions (`"${var.name_prefix}-alb"` etc.).
- **`tenant_domain` regex** — the exact validation regex (a reasonable domain pattern, e.g. one that rejects empty string and obviously-invalid hosts) is the planner's discretion; the hard requirement is "non-empty, plausibly a domain." Same regex reused in `acm` and `route53`.
- **fixed-response 503 body/content-type** — short plain-text body (e.g. `"No tenant provisioned"`) at the planner's discretion; only the `503` status matters.
- **Whether to also export `alb_arn` / `alb_dns_name` / `cert_domain` / `zone_name_servers`** — only `cert_arn`, `listener_arn`, `hosted_zone_id` are contractually required (TLS-02). Add extras only if cheap and clearly useful; don't expand the provisioner contract gratuitously.
- **route53 `force_destroy`** — planner's discretion (zone has no TF-managed records, so either is offline-safe).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & project scope
- `.planning/REQUIREMENTS.md` — ACM-01 (wildcard cert `*.{tenant_domain}`, DNS validation), ALB-01 (shared ALB, HTTPS listener with ACM cert, `idle_timeout > 60`, no per-tenant TGs/host rules), DNS-01 (public hosted zone for `tenant_domain`, no per-tenant records), TLS-02 (calls + three outputs uncommented/wired).
- `.planning/ROADMAP.md` §"Phase 5: TLS and routing" — goal + 5 success criteria (the locked acm/route53/alb shapes, wiring order, full-contract plan-check).
- `.planning/PROJECT.md` — core value, constraints (no NAT, `name_prefix` on every resource, all wiring in `envs/prod/main.tf` with no module-to-module calls, code-complete verification, cost-stripping theme), host-based ALB routing note (`{slug}.{tenant_domain}`, wildcard cert).

### Prior-phase decisions to honor
- `.planning/phases/04-shared-filesystem/04-CONTEXT.md` — offline-plan discipline (no live data sources / `skip_*` flags); cost-lean MVP pattern with "deferred, not rejected" hardening framing (the template for D-04 access-logs-off); pre-declare module variables before uncommenting; underscore module labels; "don't expand the provisioner contract gratuitously."
- `.planning/phases/03-databases-and-secrets/03-CONTEXT.md` — `enable_*` count-gating pattern (e.g. `enable_rds_proxy`) as the template for any future feature toggle; pre-declare variables; underscore module labels.
- `.planning/phases/01-networking-module/01-CONTEXT.md` — the offline dummy-AWS env behind `make plan-check`; `name_prefix` + provider `default_tags` patterns; the ALB SG (`module.networking.alb_security_group_id`, ingress 80/443 from internet) and public-subnet layout the ALB consumes.

### Existing architecture & conventions (codebase maps)
- `.planning/codebase/ARCHITECTURE.md` — root-module composition, `name_prefix`, anti-patterns (no module-to-module calls, no hardcoded names), the typed provisioner output contract.
- `.planning/codebase/CONVENTIONS.md` — module interface / variable / output naming; module dirs use hyphens, labels use underscores.
- `.planning/codebase/CONCERNS.md` — pre-declare module variables before uncommenting calls; offline-plan constraints; `tenant_domain` validation guard against empty-string default.

### Files to implement / edit
- `modules/acm/{main,variables,outputs}.tf` — stub today. Add: `aws_acm_certificate` (wildcard `*.{tenant_domain}`, `validation_method=DNS`, `create_before_destroy`), `tenant_domain` variable + regex `validation`, `cert_arn` output.
- `modules/route53/{main,variables,outputs}.tf` — stub today. Add: `aws_route53_zone` (public, `tenant_domain`), `tenant_domain` variable + regex `validation`, `hosted_zone_id` output. No records.
- `modules/alb/{main,variables,outputs}.tf` — stub today. Add: `aws_lb` (internet-facing application, lean toggles per D-04), HTTP:80 redirect listener + HTTPS:443 listener (cert, `idle_timeout > 60`, 503 default), `acm_cert_arn` + subnet/SG/`vpc_id` variables, `listener_arn` output (the **HTTPS** listener).
- `envs/prod/main.tf` — uncomment + wire `module "acm"`, `module "alb"` (after acm), `module "route53"` (build step 6); thread `name_prefix`, `tenant_domain`, `module.acm.cert_arn`, and the ALB subnets/SG.
- `envs/prod/outputs.tf` — uncomment `alb_listener_arn` (~31-33), `hosted_zone_id` (~56-58), `acm_cert_arn` (~61-63).

### External (architecture source of truth, outside this repo)
- `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md` — host-based routing, idle timeout > 60s, "route only 8069", `healthCheckGracePeriod >= 240s` for first-boot (a target-group/ECS-service property — adapter-owned, NOT created here); per-tenant DNS records, target groups, and host rules created by the adapter at provision time.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `local.name_prefix = "${var.project}-${var.environment}"` (= `odoo-saas-prod`) in `envs/prod/main.tf` — pass as each module's `name_prefix`.
- `var.tenant_domain` (`envs/prod/variables.tf:19`) already exists with a `""` default + `# TODO: set in terraform.tfvars before building route53/acm/alb` marker — feeds `acm` and `route53`. (The empty default is why criteria #1/#2 demand a regex `validation` block in the modules.)
- `module.networking.alb_security_group_id` (already an active output, `envs/prod/outputs.tf:26-28`; ingress 80/443 from internet) → the ALB's security group. `module.networking.private_subnet_ids` (public subnets across ≥2 AZs) → the ALB's subnets. Both already wired and plan-green from Phase 1.
- Commented stub blocks already sketch the interface: `module "acm"` / `module "alb"` / `module "route53"` at the bottom of `envs/prod/main.tf`, and the three outputs in `envs/prod/outputs.tf`. The `alb` stub call is **incomplete** — it lacks subnets/SG (see Claude's Discretion D-04 wiring note).
- Phases 1–4 implemented and wired; `make plan-check` is green at 31 resources — Phase 5 must keep it green and grow the count (completing the contract).

### Established Patterns
- Modules receive inputs via variables, expose typed outputs consumed only by the root config (no cross-module references — all wiring in `envs/prod/main.tf`).
- Resource names `"${var.name_prefix}-<thing>"`; never hardcoded. Module dirs use hyphens (`route53/` is already underscore-free), labels referenced with underscores (`module.acm.*`, `module.alb.*`, `module.route53.*`).
- `make fmt` / `make validate` wrap `terraform fmt -recursive` / `validate`; **`make plan-check`** is the offline gate (memory: use `make plan-check`, NOT `make plan`).
- Variables get prod-sensible defaults so the plan runs with zero tfvars editing; required-but-empty values (`tenant_domain`) keep the `# TODO: set in terraform.tfvars` marker and rely on the regex `validation` block to fail loudly if left empty at real plan-time. (The offline gate supplies a dummy value — see the Makefile/plan-check env.)
- Count-gating via an `enable_*` flag (Phase 3 `enable_rds_proxy`) is the template if any toggle is ever added — but D-04 keeps the ALB lean with no toggle.

### Integration Points
- `module.acm.cert_arn` → ALB HTTPS listener `certificate_arn` (in-root wiring) **and** → `envs/prod/outputs.tf` `acm_cert_arn` → provisioner `aws_acm_cert_arn`.
- `module.alb.listener_arn` (the HTTPS:443 listener) → `envs/prod/outputs.tf` `alb_listener_arn` → provisioner `aws_alb_listener_arn` (the adapter attaches per-tenant host rules/target groups to this listener).
- `module.route53.hosted_zone_id` → `envs/prod/outputs.tf` `hosted_zone_id` → provisioner `aws_hosted_zone_id` (the adapter adds per-tenant records into this zone).
- No new provider dependency — `hashicorp/aws ~> 6.0` covers acm/alb/elbv2/route53. (`hashicorp/random` already added in Phase 3.)

</code_context>

<specifics>
## Specific Ideas

- Consistent theme across all four decisions: **maximum decoupling + leanest offline-plan-safe shape.** acm doesn't know about route53 (D-02), route53 doesn't know about alb (D-03), and the ALB carries no cost-bearing extras (D-04). This keeps the three new modules independent (matching the no-module-to-module-calls architecture) and avoids apply-time-only resources that do nothing under the code-complete-only gate.
- The 503 (not 404) default action is a deliberate semantic choice — an unrouted host means "no tenant provisioned here yet," which the adapter will resolve by adding a host rule, not a missing page.
- The user continues the Phase 3/4 posture: cost-lean MVP defaults with "deferred, not rejected" framing for hardening (access logs), and free hardening kept on (`drop_invalid_header_fields`, http2, ACM `create_before_destroy`).

</specifics>

<deferred>
## Deferred Ideas

- **ACM DNS validation chain** (`aws_route53_record` for `domain_validation_options` + `aws_acm_certificate_validation`) — deferred from this phase (D-02); needed for a real `terraform apply` to produce an ISSUED cert, but a no-op under the code-complete-only/offline gate. Revisit when the milestone moves past plan-only to a real apply.
- **Fleet-wide wildcard `*.{tenant_domain}` ALIAS → ALB record** — deferred (D-03); would let every tenant subdomain resolve without per-tenant DNS. Revisit only if the provisioner design decides fleet-wide DNS belongs in the baseline rather than the adapter.
- **ALB access logs** (S3 bucket + bucket policy + `access_logs` block) — deferred hardening item (D-04), consistent with EFS-backups-off / RDS-proxy-off; revisit alongside the broader observability/security hardening pass.
- **`healthCheckGracePeriod >= 240s` and per-tenant target groups / host rules / DNS records** — explicitly NOT Terraform's job this milestone; owned by the provisioner `AwsDeploymentAdapter` at provision time (target groups + host rules attach to the exported `listener_arn`; records go into the exported `hosted_zone_id`).

### Reviewed Todos (not folded)
None — the two STATE.md pending todos (pre-declare `tenant_domain`/`acm_cert_arn` variables; add `tenant_domain` `validation` blocks) are **folded** into the locked Phase Boundary above, as they're already mandated by ROADMAP criteria #1/#2 and CONCERNS.md.

</deferred>

---

*Phase: 5-tls-and-routing*
*Context gathered: 2026-06-24*
