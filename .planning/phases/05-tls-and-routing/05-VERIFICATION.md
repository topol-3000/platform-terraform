---
phase: 05-tls-and-routing
verified: 2026-06-24T12:00:00Z
status: passed
score: 7/7 must-haves verified
overrides_applied: 0
human_decision: "CR-01 accepted as-is by developer 2026-06-24 — regex guard is intentional; make plan-check is the milestone gate; tenant_domain required in terraform.tfvars per CLAUDE.md. No code change."
human_verification:
  - test: "Confirm CR-01 disposition: plain make plan fails with empty tenant_domain"
    expected: >
      Either (a) accept the regression as-is because CLAUDE.md documents tenant_domain
      as a required deployment variable and make plan-check is the milestone gate; or
      (b) fix by adding count gating or relaxing the module-level validation. Decision
      determines whether WR-01 (tenant_domain = "" breaks make plan) is a known
      acceptable limitation or a pre-apply blocker that must be resolved now.
    why_human: >
      The CLAUDE.md "Core Value" states terraform in envs/prod produces a correct
      well-formed plan. The review correctly flags that plain make plan (exit 1) is
      now broken for the default config. However the same file says tenant_domain must
      be set before building these modules, and make plan-check is the documented
      code-complete gate. Only the developer can decide if the Core Value clause applies
      to the un-set default case or only to deployments with tenant_domain set.
---

# Phase 5: TLS and Routing Verification Report

**Phase Goal:** modules/acm, modules/alb, and modules/route53 are implemented and wired
into envs/prod — a wildcard ACM cert covers *.{tenant_domain}, the shared ALB has an HTTPS
listener using that cert with idle timeout >60s, and the Route53 hosted zone is declared for
tenant_domain. The acm_cert_arn, alb_listener_arn, and hosted_zone_id contract outputs are
exported and `make plan-check` is green, completing the full provisioner output contract.

**Verified:** 2026-06-24T12:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | modules/acm declares a wildcard ACM certificate for *.{tenant_domain} using DNS validation | VERIFIED | `modules/acm/main.tf:11-12`: `resource "aws_acm_certificate" "wildcard"` with `domain_name = "*.${var.tenant_domain}"`, `validation_method = "DNS"` |
| 2 | modules/acm declares the bare certificate only — no aws_acm_certificate_validation resource (D-02) | VERIFIED | `modules/acm/main.tf:10`: comment explains omission; grep finds only comment, no resource declaration |
| 3 | modules/route53 declares a public hosted zone for tenant_domain with no records of any kind (D-03) | VERIFIED | `modules/route53/main.tf:11-14`: `aws_route53_zone.main` with `name = var.tenant_domain`, `force_destroy = false`; no `vpc` block; no `aws_route53_record` resources |
| 4 | Both modules guard against empty-string tenant_domain via a regex validation block | VERIFIED | `modules/acm/variables.tf:10-13` and `modules/route53/variables.tf:10-13`: identical `can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))` |
| 5 | modules/alb declares a shared internet-facing ALB with idle_timeout > 60, HTTP->HTTPS redirect, and HTTPS:443 listener with ACM cert | VERIFIED | `modules/alb/main.tf`: `aws_lb.main` with `idle_timeout = 120` (on the LB, not listener), `aws_lb_listener.http` (301 redirect), `aws_lb_listener.https` with `certificate_arn = var.acm_cert_arn` and `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` |
| 6 | acm, alb, and route53 modules are uncommented and wired into envs/prod/main.tf with correct arguments | VERIFIED | `envs/prod/main.tf:93-111`: three active module blocks — acm before alb (line 93 < line 99), alb expanded with `subnet_ids = module.networking.private_subnet_ids` and `security_group_id = module.networking.alb_security_group_id`, route53 with `name_prefix` added |
| 7 | acm_cert_arn, alb_listener_arn, and hosted_zone_id contract outputs are exported; make plan-check is green | VERIFIED | `envs/prod/outputs.tf:31-64`: three active outputs; `make plan-check` exits 0 with 36 resources; plan contains `module.acm.aws_acm_certificate.wildcard`, `module.alb.aws_lb.main`, `module.alb.aws_lb_listener.http`, `module.alb.aws_lb_listener.https`, `module.route53.aws_route53_zone.main` |

**Score:** 7/7 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `modules/acm/main.tf` | `aws_acm_certificate.wildcard` with DNS validation, `create_before_destroy`, no `name` arg, no validation chain resource | VERIFIED | Matches exactly. Comment on line 10 documents D-02 deferred validation chain. |
| `modules/acm/variables.tf` | `name_prefix` + `tenant_domain` with `can(regex(...)` validation | VERIFIED | Both variables present; `can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$"...))` block on `tenant_domain`. |
| `modules/acm/outputs.tf` | `cert_arn` -> `aws_acm_certificate.wildcard.arn` | VERIFIED | Output present with provisioner contract description. |
| `modules/route53/main.tf` | `aws_route53_zone.main` with `name = var.tenant_domain`, `force_destroy = false`, no vpc, no records | VERIFIED | All four conditions met. |
| `modules/route53/variables.tf` | `name_prefix` + `tenant_domain` with identical validation block | VERIFIED | Regex pattern is character-for-character identical to `modules/acm/variables.tf`. |
| `modules/route53/outputs.tf` | `hosted_zone_id` -> `aws_route53_zone.main.zone_id` | VERIFIED | Uses `.zone_id` (explicit, not `.id`). |
| `modules/alb/main.tf` | `aws_lb.main` (idle_timeout=120, drop_invalid_header_fields=true, enable_http2=true) + `aws_lb_listener.http` (301 redirect) + `aws_lb_listener.https` (TLS 1.3 policy, fixed-response 503) | VERIFIED | All three resources present with correct attribute values. No `idle_timeout` on listeners. `ssl_policy` only on HTTPS listener. |
| `modules/alb/variables.tf` | `name_prefix`, `acm_cert_arn`, `subnet_ids` (list(string)), `security_group_id` | VERIFIED | All four variables present, all required (no defaults). |
| `modules/alb/outputs.tf` | `listener_arn` -> `aws_lb_listener.https.arn` | VERIFIED | Output present with provisioner contract description. |
| `Makefile` | `plan-check` target injects `-var "tenant_domain=placeholder.example.com"` | VERIFIED | `Makefile:48` contains the exact injection in the `terraform plan -input=false` command. |
| `envs/prod/main.tf` | Three active module calls (acm, alb, route53); acm before alb; alb with all four args | VERIFIED | `acm` at line 93, `alb` at line 99 (order correct). `alb` call has all required args including `module.networking.alb_security_group_id`. No commented stubs remain. |
| `envs/prod/outputs.tf` | `alb_listener_arn`, `hosted_zone_id`, `acm_cert_arn` — all active (uncommented) | VERIFIED | All three outputs active, pointing to `module.alb.listener_arn`, `module.route53.hosted_zone_id`, `module.acm.cert_arn` respectively. |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `modules/acm/main.tf` | `modules/acm/variables.tf` | `var.tenant_domain` | WIRED | `"*.${var.tenant_domain}"` in `domain_name` attribute |
| `modules/acm/outputs.tf` | `modules/acm/main.tf` | `aws_acm_certificate.wildcard.arn` | WIRED | `value = aws_acm_certificate.wildcard.arn` |
| `modules/route53/outputs.tf` | `modules/route53/main.tf` | `aws_route53_zone.main.zone_id` | WIRED | `value = aws_route53_zone.main.zone_id` |
| `modules/alb/main.tf (aws_lb_listener.https)` | `modules/alb/variables.tf` | `certificate_arn = var.acm_cert_arn` | WIRED | `alb/main.tf:52` |
| `modules/alb/outputs.tf` | `modules/alb/main.tf` | `aws_lb_listener.https.arn` | WIRED | `value = aws_lb_listener.https.arn` |
| `envs/prod/main.tf module.alb` | `envs/prod/main.tf module.acm` | `acm_cert_arn = module.acm.cert_arn` | WIRED | `main.tf:102`; `acm` at line 93 declares before `alb` at line 99 |
| `envs/prod/main.tf module.alb` | `envs/prod/main.tf module.networking` | `subnet_ids = module.networking.private_subnet_ids`, `security_group_id = module.networking.alb_security_group_id` | WIRED | `main.tf:103-104` |
| `envs/prod/outputs.tf` | `envs/prod/main.tf` | `module.alb.listener_arn` / `module.acm.cert_arn` / `module.route53.hosted_zone_id` | WIRED | All three outputs point to correct module attributes; confirmed active in plan output. |
| `Makefile plan-check` | `modules/acm + modules/route53 validation blocks` | `-var tenant_domain=placeholder.example.com` | WIRED | `Makefile:48`; satisfies `^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$` regex |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `terraform fmt -check -recursive` passes | `make plan-check` (first step) | `Success! The configuration is valid.` (exit 0) | PASS |
| `terraform validate` passes | `make plan-check` (second step) | `Success! The configuration is valid.` (exit 0) | PASS |
| `terraform plan` is non-empty with 5 new resources | `make plan-check` (third step) | `Plan: 36 to add, 0 to change, 0 to destroy.` (exit 0) | PASS |
| ACM, ALB (2 listeners), Route53 appear in plan | Inspect plan output | `module.acm.aws_acm_certificate.wildcard`, `module.alb.aws_lb.main`, `module.alb.aws_lb_listener.http`, `module.alb.aws_lb_listener.https`, `module.route53.aws_route53_zone.main` | PASS |
| Three contract outputs resolve | Inspect plan `Changes to Outputs` | `acm_cert_arn`, `alb_listener_arn`, `hosted_zone_id` all show `(known after apply)` | PASS |
| Plain `make plan` without tenant_domain fails | `terraform plan -input=false` (no `-var` injection) | Exits 1 with two `Error: Invalid value for variable` messages for `modules/acm` and `modules/route53` | CONFIRMS CR-01 |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ACM-01 | 05-01-PLAN.md, 05-03-PLAN.md | `modules/acm` declares wildcard ACM certificate for `*.{tenant_domain}` using DNS validation | SATISFIED | `modules/acm/main.tf` contains `aws_acm_certificate.wildcard` with `domain_name = "*.${var.tenant_domain}"`, `validation_method = "DNS"`, `create_before_destroy = true` |
| ALB-01 | 05-02-PLAN.md, 05-03-PLAN.md | `modules/alb` declares shared ALB with HTTPS listener using ACM cert and `idle_timeout > 60` | SATISFIED | `modules/alb/main.tf`: `aws_lb.main` (`idle_timeout = 120`), `aws_lb_listener.https` with `certificate_arn = var.acm_cert_arn` and `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` |
| DNS-01 | 05-01-PLAN.md, 05-03-PLAN.md | `modules/route53` declares public hosted zone for `tenant_domain` | SATISFIED | `modules/route53/main.tf`: `aws_route53_zone.main` with `name = var.tenant_domain`, `force_destroy = false`, no records, public (no `vpc` block) |
| TLS-02 | 05-03-PLAN.md | `acm`, `alb`, and `route53` calls and the `acm_cert_arn` / `alb_listener_arn` / `hosted_zone_id` outputs are uncommented and wired | SATISFIED | `envs/prod/main.tf:93-111` three active module calls; `envs/prod/outputs.tf` three active outputs; `make plan-check` green at 36 resources |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `modules/alb/main.tf` | 25 | `tags = { Name = "..." }` per-resource tag block | Warning | Violates CLAUDE.md "no per-resource `tags = {}` blocks" convention (review WR-03). Pre-existing pattern in `modules/networking/main.tf` also uses `Name` tags; de facto exception exists but undocumented. |

No TBD, FIXME, or XXX markers found in any phase-5 modified file. No stubs or placeholder return values found. No empty implementations.

---

## Human Verification Required

### 1. CR-01 Disposition: plain `make plan` fails for default tenant_domain=""

**Test:** Run `make plan` without setting `tenant_domain` in `terraform.tfvars`. Confirm it exits non-zero with validation errors from `modules/acm` and `modules/route53`.

**Expected:** One of two outcomes depending on decision:
- (Accept) The regression is acceptable: CLAUDE.md documents `tenant_domain` must be set before building these modules, `make plan-check` is the code-complete gate, and no downstream deployment runs `make plan` with an empty domain. The stale TODO comment on the root `tenant_domain` default becomes a latent confusion risk but not a functional gap.
- (Fix) Add `count = var.tenant_domain == "" ? 0 : 1` to `module "acm"` and `module "route53"` in `envs/prod/main.tf`, and update `module "alb"` to use `one(module.acm[*].cert_arn)` for the `acm_cert_arn` argument. This restores the "correct plan for any config" property while preserving the validation guard.

**Why human:** The CLAUDE.md "Core Value" clause ("produces a correct, well-formed plan") is ambiguous: does it apply to the undocumented default config (empty `tenant_domain`) or only to deployments where the required variables are set? Only the developer can decide which interpretation is authoritative and whether the regression needs to be fixed before this phase is closed.

---

## Gaps Summary

No automated gaps found. All 7 observable truths are VERIFIED. All 12 required artifacts exist, are substantive, and are wired. All 8 key links are connected. All 4 requirement IDs (ACM-01, ALB-01, DNS-01, TLS-02) are satisfied. `make plan-check` exits 0 with 36 resources and all three contract outputs resolved.

The single human-decision item (CR-01) is a design tradeoff between the module-level validation guards (which actively protect deployment correctness) and the plain-plan usability for the empty-default case. It does not block the phase goal as defined — the goal specifies `make plan-check` as the gate, which is green.

WR-01 through WR-05 from the code review are informational quality items:
- **WR-01** (no apex SAN): architectural limitation, not a phase-5 deliverable.
- **WR-02** (un-validated cert blocks real apply): explicitly D-02/deferred; milestone is plan-only.
- **WR-03** (per-resource `tags = {}`): existing pattern in networking module; naming inconsistency worth resolving in CLAUDE.md but not a phase blocker.
- **WR-04** (misleading subnet name): pre-existing naming from Phase 1; functional wiring is correct.
- **WR-05** (`drop_invalid_header_fields`): needs a comment; no functional gap for plan-only milestone.

---

_Verified: 2026-06-24T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
