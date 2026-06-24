---
phase: 05-tls-and-routing
plan: "01"
subsystem: acm, route53
tags: [acm, route53, tls, dns, wildcard-certificate, hosted-zone, terraform-validation]
dependency_graph:
  requires:
    - phase: 01-networking-module
      provides: "networking outputs consumed by the eventual ALB wiring (plan 05-02)"
  provides:
    - "modules/acm implemented: wildcard ACM certificate with DNS validation, cert_arn output"
    - "modules/route53 implemented: public hosted zone, hosted_zone_id output"
  affects: [05-02-PLAN.md (alb wiring consumes module.acm.cert_arn), 05-03-PLAN.md (plan-check gate requires both modules wired)]
tech_stack:
  added: []
  patterns:
    - "can(regex(...)) validation block for tenant_domain in both modules — identical guard in two independent modules"
    - "create_before_destroy lifecycle on aws_acm_certificate for zero-downtime cert rotation"
    - "aws_route53_zone with force_destroy = false — protects hosted zone from accidental destroy"
    - "Bare cert only (D-02): no aws_acm_certificate_validation resource; deferred to real apply"
key_files:
  created: []
  modified:
    - modules/acm/main.tf
    - modules/acm/variables.tf
    - modules/acm/outputs.tf
    - modules/route53/main.tf
    - modules/route53/variables.tf
    - modules/route53/outputs.tf
key_decisions:
  - "No aws_acm_certificate_validation resource (D-02): bare cert only, validation chain deferred to real apply — keeps offline plan safe"
  - "No aws_route53_record resources (D-03): provisioner adapter owns all per-tenant DNS records at provision time"
  - "Identical regex validation blocks in both modules: can(regex(\"^[a-z0-9][a-z0-9.-]+\\\\.[a-z]{2,}$\", var.tenant_domain)) — same guard, no divergence"
  - "aws_acm_certificate has no name argument: resource is identified by domain_name, not name_prefix"
  - "aws_route53_zone uses name = var.tenant_domain (domain identity), not name_prefix — zone is the domain itself"
patterns_established:
  - "Pattern: can(regex(...)) validation for tenant_domain — copy identical block to any future module accepting tenant_domain"
  - "Pattern: bare ACM cert without validation chain — offline-plan-safe; add aws_acm_certificate_validation only at real-apply hardening pass"
requirements_completed:
  - ACM-01
  - DNS-01
duration: ~4min
completed: "2026-06-24"
---

# Phase 5 Plan 1: ACM and Route53 Module Implementation Summary

**Wildcard ACM certificate (DNS validation, create_before_destroy) and public Route53 hosted zone — both with regex-validated tenant_domain inputs and provisioner contract outputs**

## Performance

- **Duration:** ~4 minutes
- **Started:** 2026-06-24T11:15:03Z
- **Completed:** 2026-06-24T11:18:40Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- `modules/acm` fully implemented: `aws_acm_certificate.wildcard` with `domain_name = "*.${var.tenant_domain}"`, `validation_method = "DNS"`, `lifecycle { create_before_destroy = true }`, and `cert_arn` output. No `aws_acm_certificate_validation` resource (D-02 — deferred to real apply).
- `modules/route53` fully implemented: `aws_route53_zone.main` with `name = var.tenant_domain`, `force_destroy = false`, and `hosted_zone_id` output using `.zone_id`. No records, no `vpc` block (public zone; per D-03 adapter owns per-tenant records).
- Both modules guard against empty/invalid `tenant_domain` with identical `can(regex(...))` validation blocks — satisfies threat mitigations T-05-01 and T-05-02.
- `terraform fmt -check -recursive` and `terraform validate` pass for both modules independently.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement modules/acm** - `a3bd870` (feat)
2. **Task 2: Implement modules/route53** - `a3bb986` (feat)

## Files Created/Modified

- `modules/acm/main.tf` — `aws_acm_certificate.wildcard` with DNS validation and create_before_destroy lifecycle
- `modules/acm/variables.tf` — `name_prefix` + `tenant_domain` with regex validation block
- `modules/acm/outputs.tf` — `cert_arn` output pointing to `aws_acm_certificate.wildcard.arn`
- `modules/route53/main.tf` — `aws_route53_zone.main` with `name = var.tenant_domain`, `force_destroy = false`
- `modules/route53/variables.tf` — `name_prefix` + `tenant_domain` with identical validation block
- `modules/route53/outputs.tf` — `hosted_zone_id` output pointing to `aws_route53_zone.main.zone_id`

## Decisions Made

- **D-02 respected**: No `aws_acm_certificate_validation` resource — the cert is declared but its validation chain (DNS record + polling) is deferred to real apply time. This keeps the offline plan gate clean and is noted in a comment in `modules/acm/main.tf`.
- **D-03 respected**: No `aws_route53_record` resources of any kind — all per-tenant DNS records are adapter-owned at provision time. No fleet-wide wildcard ALIAS records.
- **Identical validation blocks**: Both `modules/acm/variables.tf` and `modules/route53/variables.tf` use the same regex `^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$` with the same error message — no divergence between the two guards.
- **No `name` argument on ACM cert**: `aws_acm_certificate` does not support a `name` attribute (unsupported argument error if added); resource is identified by `domain_name`.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

Module-level `terraform validate` required `terraform init` to install the AWS provider into the module's `.terraform/` directory (no provider configured at module level, only at `envs/prod`). This is expected behavior — ran `terraform init` in each module directory before validate. Both validated successfully after init.

## Threat Surface Scan

Both threat mitigations from the plan's threat register are implemented:

- **T-05-01** (Tampering — modules/acm tenant_domain): `can(regex(...))` validation block in `modules/acm/variables.tf` rejects empty string and invalid domains before any resource is planned.
- **T-05-02** (Tampering — modules/route53 tenant_domain): identical validation block in `modules/route53/variables.tf`.
- **T-05-03** (Info Disclosure — cert_arn output): `cert_arn` is a non-secret ARN identifier; no credentials or private key material in outputs. ACM manages cert lifecycle and private key internally.
- **T-05-04** (Spoofing — public Route53 zone): Zone is not created until real `terraform apply`; this plan is plan-only/offline. Accepted disposition.

No new security-relevant surface beyond what the plan anticipated.

## Known Stubs

None — both modules are fully implemented. The only intentional omissions are `aws_acm_certificate_validation` (D-02, deferred) and `aws_route53_record` (D-03, adapter-owned), both documented in comments.

## User Setup Required

None — no external service configuration required. Both modules validate offline with no AWS credentials.

## Next Phase Readiness

- `modules/acm` exports `cert_arn` — ready to be consumed by `module.alb` in plan 05-02.
- `modules/route53` exports `hosted_zone_id` — ready for `envs/prod/outputs.tf` wiring in plan 05-03.
- Both modules pass `terraform validate` independently; the full `make plan-check` gate runs in plan 05-03 after all three modules are wired into `envs/prod`.

## Self-Check

### Created/Modified Files Exist

- `modules/acm/main.tf` — `aws_acm_certificate.wildcard`, lifecycle, no validation chain resource
- `modules/acm/variables.tf` — name_prefix + tenant_domain with regex validation
- `modules/acm/outputs.tf` — cert_arn output
- `modules/route53/main.tf` — `aws_route53_zone.main`, force_destroy = false, no records
- `modules/route53/variables.tf` — name_prefix + tenant_domain with identical regex validation
- `modules/route53/outputs.tf` — hosted_zone_id output

### Commits Exist

- a3bd870: feat(05-01): implement modules/acm — wildcard ACM certificate with DNS validation
- a3bb986: feat(05-01): implement modules/route53 — public hosted zone for tenant domain

## Self-Check: PASSED
