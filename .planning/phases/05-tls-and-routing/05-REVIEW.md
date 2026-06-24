---
phase: 05-tls-and-routing
reviewed: 2026-06-24T00:00:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - Makefile
  - envs/prod/main.tf
  - envs/prod/outputs.tf
  - modules/acm/main.tf
  - modules/acm/outputs.tf
  - modules/acm/variables.tf
  - modules/alb/main.tf
  - modules/alb/outputs.tf
  - modules/alb/variables.tf
  - modules/route53/main.tf
  - modules/route53/outputs.tf
  - modules/route53/variables.tf
findings:
  critical: 1
  warning: 5
  info: 3
  total: 9
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-06-24
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Phase 05 implements the routing/TLS layer: a wildcard ACM certificate (`modules/acm`),
an internet-facing ALB with HTTP→HTTPS redirect and HTTPS termination (`modules/alb`),
and a public Route53 hosted zone (`modules/route53`), wired together in
`envs/prod/main.tf` and re-exported via `envs/prod/outputs.tf`.

The HCL is well-formed and the module-interface conventions (single `name_prefix`,
no cross-module calls, `default_tags`-only tagging) are mostly respected. However, the
review surfaced one BLOCKER that breaks the plain `make plan` path for any deployment
that has not set `tenant_domain`, plus several WARNINGs around the wildcard cert not
covering the configured zone apex, the cert-validation gap that will fail a real
`apply`, a per-resource `tags` block that violates the project's tagging convention,
and a stated-vs-actual mismatch between the ALB and the `internal` flag / subnet source.

Note: the region default across the root config is `us-east-1` (variables.tf, backend.tf,
tfvars.example), but CLAUDE.md states the project default is `eu-central-1`. That
mismatch lives in files outside this phase's review scope (`backend.tf`, `variables.tf`
were not in the changed-file set) and is therefore not counted as a phase-05 finding,
but it is flagged in IN-03 for visibility because it affects the ACM/ALB region binding.

## Critical Issues

### CR-01: `tenant_domain` validation regex rejects the `""` default, breaking plain `terraform plan`

**File:** `modules/acm/variables.tf:10-13`, `modules/route53/variables.tf:10-13` (and the root default at `envs/prod/variables.tf:26`)
**Issue:**
Phase 05 added `validation {}` blocks to the `tenant_domain` variable in both the `acm`
and `route53` modules:

```hcl
condition = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))
```

The root variable `envs/prod/variables.tf` still defaults `tenant_domain` to `""`
(with the comment "TODO: set in terraform.tfvars before building route53/acm/alb").
With the `acm` and `route53` modules now unconditionally instantiated in
`envs/prod/main.tf` (lines 93-97 and 107-111), an operator who runs `make plan` (or
`terraform plan`) without having set `tenant_domain` will now hit a hard validation
error — the empty string fails the regex — instead of producing a plan. Before this
phase the modules were stubs, so `""` was harmless; the build order comment is now stale.

This regresses the project's "Core Value" guarantee that `terraform` in `envs/prod`
"produces a correct, well-formed plan." `make plan-check` masks the problem because it
injects `-var "tenant_domain=placeholder.example.com"` (Makefile:48), but the real
`make plan` target (Makefile:21) passes no such var and will fail validation for the
default config.

**Fix:** Either make the routing/TLS modules conditional on a non-empty domain, or give
the root variable a real default and drop the empty-string sentinel. The cleanest option
that preserves the offline gate is to gate the three modules with `count`:

```hcl
# envs/prod/main.tf
module "acm" {
  source        = "../../modules/acm"
  count         = var.tenant_domain == "" ? 0 : 1
  name_prefix   = local.name_prefix
  tenant_domain = var.tenant_domain
}
# (and likewise route53; alb's acm_cert_arn ref then becomes one(module.acm[*].cert_arn))
```

Alternatively, relax the module-level validations to also accept `""` and rely on the
documented "set before building" workflow. Pick one — the current state fails `plan`
for the documented default.

## Warnings

### WR-01: Wildcard cert `*.{tenant_domain}` does not cover the zone apex, and there is no apex SAN

**File:** `modules/acm/main.tf:11-12`, `modules/route53/main.tf:11-14`
**Issue:**
The ACM certificate requests only `*.${var.tenant_domain}` (line 12). The Route53 zone
is created for the bare apex `var.tenant_domain` (route53/main.tf:13). An RFC-6125
wildcard matches exactly one label, so `*.saas.example.com` covers `acme.saas.example.com`
but NOT `saas.example.com` itself. If anything is ever served at the apex (a marketing
page, a health check, the `provisioner` control-plane host, or a tenant landing on the
bare domain), the HTTPS:443 listener will present a cert that fails hostname verification.
SEED-001 says tenants are `{slug}.{tenant_domain}`, so subdomains are covered — but the
absence of an apex SAN is an undocumented limitation worth an explicit decision.

**Fix:** If apex serving is ever needed, add it as a SAN:

```hcl
resource "aws_acm_certificate" "wildcard" {
  domain_name               = "*.${var.tenant_domain}"
  subject_alternative_names = [var.tenant_domain]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
}
```

If apex serving is intentionally out of scope, add a comment in `acm/main.tf` recording
that decision so the gap is not mistaken for a bug later.

### WR-02: HTTPS listener references an un-validated certificate — real `apply` will fail

**File:** `modules/alb/main.tf:47-52`, `modules/acm/main.tf:9-18`
**Issue:**
The `acm` module deliberately omits `aws_acm_certificate_validation` and creates no
Route53 validation records (acm/main.tf:9-10, "validation chain deferred"). The ALB
HTTPS listener sets `certificate_arn = var.acm_cert_arn` (alb/main.tf:52) pointing at
that un-validated cert. AWS rejects attaching a certificate that is in
`PENDING_VALIDATION` to a listener — a real `terraform apply` will error at the listener
resource even though `plan` succeeds. The CLAUDE.md milestone is "code-complete /
plan-only," so this does not break the current gate, but the routing layer is not
apply-ready: the validation records (in route53) and an `aws_acm_certificate_validation`
gate are missing, and there is nothing in the code recording that `apply` is expected to
fail. This couples three modules (acm produces validation options, route53 must host the
records, alb consumes the validated arn) with the middle link absent.

**Fix:** Document the apply-time dependency explicitly, and when moving past plan-only add
the validation wiring in the root (cross-module wiring belongs in `envs/prod/main.tf`):
the `aws_acm_certificate.wildcard.domain_validation_options` feed `aws_route53_record`
entries in the zone, then an `aws_acm_certificate_validation` resource gates the arn the
ALB listener consumes. At minimum, add a comment on the HTTPS listener noting it requires
a validated cert so the deferred work is traceable.

### WR-03: Per-resource `tags = {}` on `aws_lb` violates the project tagging convention

**File:** `modules/alb/main.tf:25`
**Issue:**
CLAUDE.md states tags are "Applied exclusively via the provider-level `default_tags`
block — no per-resource `tags = {}` blocks." The ALB adds `tags = { Name = "${var.name_prefix}-alb" }`
(line 25). While the networking module also uses per-resource `Name` tags (a pre-existing
pattern), the documented convention forbids per-resource `tags`. If this is an accepted
exception for `Name` tags it should be written into CLAUDE.md; as written, the new `aws_lb`
resource is inconsistent with the stated rule. Note also that the two `aws_lb_listener`
resources carry no `Name` tag, so even the `Name`-tag pattern is applied inconsistently
within this same module.

**Fix:** Either remove the per-resource `tags` block and rely on `default_tags` (adding a
`Name` tag there if a Name is desired fleet-wide is not possible since Name must be unique
— so document the `Name`-tag exception in CLAUDE.md instead), or apply `Name` tags
consistently to all taggable resources in the module. Resolve the convention ambiguity
rather than leaving a half-applied pattern.

### WR-04: ALB variable/comment claims subnets are "public" but sources `private_subnet_ids`; misleading and fragile

**File:** `modules/alb/variables.tf:11-14`, `envs/prod/main.tf:103`
**Issue:**
`aws_lb.main` sets `internal = false` (internet-facing, alb/main.tf:14) and is fed
`subnet_ids = module.networking.private_subnet_ids` (main.tf:103). The networking module's
`private_subnet_ids` output is actually the **public** subnets (networking/outputs.tf:6-8,
`aws_subnet.public[*].id` — the name is a deliberate misnomer carried from the no-NAT
design). So the wiring is functionally correct (an internet-facing ALB does need public
subnets), but the naming is actively misleading: the ALB variable description says "Public
subnet IDs ... Sourced from module.networking.private_subnet_ids" (variables.tf:12-13),
juxtaposing "public" and "private" in one sentence. A future maintainer who "fixes" the
networking module to add real private subnets, or who reads `private_subnet_ids` literally,
will place an internet-facing ALB in private subnets and silently break ingress. This is a
latent correctness trap created by reusing the misnamed output.

**Fix:** Add a dedicated public-subnet output in the networking module (e.g.
`public_subnet_ids`) and wire the ALB from that, or at minimum tighten the comment to state
that `private_subnet_ids` *is* the public-subnet set under the no-NAT design and that the
ALB depends on that fact. Do not leave the ALB silently depending on a misnamed output.

### WR-05: `drop_invalid_header_fields = true` may strip headers Odoo relies on

**File:** `modules/alb/main.tf:22`
**Issue:**
`drop_invalid_header_fields = true` causes the ALB to drop HTTP headers whose names
contain characters not valid per the HTTP spec (e.g. underscores in some configurations,
non-conforming proxy headers). Odoo behind a reverse proxy is sensitive to forwarded
headers; if any upstream component or the ECS task injects a header with a non-standard
name, it will be silently removed, producing hard-to-diagnose behavior (wrong scheme
detection, broken longpoll, session issues). This is enabled with no comment explaining
the security/compat tradeoff, unlike the rest of the well-commented module.

**Fix:** Confirm Odoo's forwarded-header set is RFC-compliant under this ALB, and add a
comment recording the decision, e.g. `# drops malformed headers; verify Odoo X-Forwarded-*
set is RFC-compliant`. If header compatibility is uncertain at this stage, default to
`false` until validated, since this is a routing layer that has not yet been exercised
end-to-end.

## Info

### IN-01: ALB has `enable_deletion_protection = false` on a shared, fleet-wide load balancer

**File:** `modules/alb/main.tf:20`
**Issue:**
The shared ALB is the single ingress point for every tenant. Deletion protection is
disabled, so a stray `terraform destroy` (the `make destroy` target exists, Makefile:54-55)
removes ingress for the whole fleet. The bootstrap S3 bucket gets `prevent_destroy`
(per CLAUDE.md) but this comparably critical resource gets none.
**Fix:** Consider `enable_deletion_protection = true` and/or a
`lifecycle { prevent_destroy = true }` on `aws_lb.main` for the production env, consistent
with the protection applied to the state bucket.

### IN-02: 503 fixed-response body is informational only; no comment on intentional content

**File:** `modules/alb/main.tf:54-62`
**Issue:**
The default HTTPS action returns a `503` with body `"No tenant provisioned"`. This leaks a
small amount of internal semantics to unauthenticated internet clients hitting the bare
listener. Low risk, but worth confirming the message is intentional and not a placeholder.
**Fix:** Keep if intentional; a generic body (e.g. "Service Unavailable") avoids exposing
provisioning internals. Add a one-line comment that the text is deliberate.

### IN-03: Region default is `us-east-1` across the root config, but CLAUDE.md mandates `eu-central-1`

**File:** out of phase-05 scope — `envs/prod/variables.tf:4`, `envs/prod/variables.tf:42`, `envs/prod/backend.tf:10`, `envs/prod/terraform.tfvars.example` (none were in the changed-file set)
**Issue:**
CLAUDE.md states: "Region: `eu-central-1` default (hardcoded in `envs/prod/backend.tf`,
defaulted in tfvars)." The actual config defaults to `us-east-1` everywhere (region var,
azs `us-east-1a/b`, backend region, tfvars.example). ACM certs and the ALB are
region-bound and must co-locate; since both run under the single root provider this is
internally consistent, but the whole stack lands in the wrong region versus the documented
intent. This is flagged for visibility only — these files are outside the phase-05 changed
set, so it is not counted as a phase-05 finding.
**Fix:** Reconcile the region. If `us-east-1` is the new intended default, update CLAUDE.md;
if `eu-central-1` is correct, fix `variables.tf`, `azs`, `backend.tf`, and `tfvars.example`.

---

_Reviewed: 2026-06-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
