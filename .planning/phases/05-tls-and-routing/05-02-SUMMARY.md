---
phase: 05-tls-and-routing
plan: 02
subsystem: alb
tags: [alb, tls, https, redirect, listener]
dependency_graph:
  requires: [modules/networking (alb_security_group_id, private_subnet_ids), modules/acm (cert_arn)]
  provides: [modules/alb (listener_arn), Makefile plan-check tenant_domain injection]
  affects: [envs/prod wiring in plan 05-03]
tech_stack:
  added: [aws_lb, aws_lb_listener]
  patterns: [multi-resource module, HTTP 301 redirect, HTTPS fixed-response 503, ELBSecurityPolicy-TLS13-1-2-2021-06]
key_files:
  created: []
  modified:
    - modules/alb/main.tf
    - modules/alb/variables.tf
    - modules/alb/outputs.tf
    - Makefile
decisions:
  - idle_timeout=120 on aws_lb (not aws_lb_listener) per SEED-001 Odoo longpoll guard
  - ssl_policy=ELBSecurityPolicy-TLS13-1-2-2021-06 satisfies ASVS V6 Cryptography L1 (T-05-06)
  - drop_invalid_header_fields=true free hardening (D-04, T-05-07)
  - enable_deletion_protection=false lean MVP posture (D-04, T-05-09)
  - No access_logs block — deferred (D-04); no S3 logging bucket this phase
  - placeholder.example.com in Makefile plan-check — satisfies regex, plainly non-real, no secret (T-05-10)
metrics:
  duration: "3m 5s"
  completed: "2026-06-24T11:18:40Z"
  tasks_completed: 2
  files_modified: 4
---

# Phase 05 Plan 02: ALB Module + Makefile plan-check Fix Summary

**One-liner:** Shared internet-facing ALB with idle_timeout=120, HTTP→HTTPS 301 redirect, HTTPS:443 TLS 1.3 termination with fixed-response 503 default, and Makefile plan-check tenant_domain dummy injection to keep the offline gate green.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Implement modules/alb (ALB + two listeners) | 0f147be | modules/alb/main.tf, modules/alb/variables.tf, modules/alb/outputs.tf |
| 2 | Update Makefile plan-check with tenant_domain dummy var | 0f7c4e3 | Makefile |

## What Was Built

### Task 1: modules/alb implementation

Three resources in `modules/alb/main.tf`:

1. `aws_lb.main` — internet-facing ALB named `${var.name_prefix}-alb`:
   - `idle_timeout = 120` (> 60 for Odoo longpoll ~50s; on the LB resource, not the listener)
   - `enable_deletion_protection = false` (lean MVP posture)
   - `enable_http2 = true`
   - `drop_invalid_header_fields = true` (free security hardening per D-04)
   - No `access_logs` block (deferred; no S3 logging bucket provisioned)

2. `aws_lb_listener.http` — port 80, protocol HTTP, redirect to HTTPS:443 with `status_code = "HTTP_301"`. No `ssl_policy` or `certificate_arn` (HTTP listener does not support these).

3. `aws_lb_listener.https` — port 443, protocol HTTPS, `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`, `certificate_arn = var.acm_cert_arn`. Default action: `fixed-response` returning 503 with message "No tenant provisioned" (provisioner adapter attaches per-tenant host rules at runtime).

Four variables in `modules/alb/variables.tf`: `name_prefix`, `acm_cert_arn`, `subnet_ids` (list(string)), `security_group_id` — all required, no defaults.

One output in `modules/alb/outputs.tf`: `listener_arn = aws_lb_listener.https.arn` with provisioner contract description `-> provisioner aws_alb_listener_arn`.

### Task 2: Makefile plan-check fix

Changed `terraform plan -input=false` to `terraform plan -input=false -var "tenant_domain=placeholder.example.com"` in the `plan-check` target. This satisfies the `can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))` validation block that will be active in `modules/acm` and `modules/route53` (implemented in plan 05-01). Without this, `make plan-check` would fail on the empty-string root default for `tenant_domain`.

## Verification Results

1. `terraform validate` in `modules/alb/` — PASS
2. `grep -c 'tenant_domain=placeholder.example.com' Makefile` — returns 1 (PASS)
3. `terraform fmt -check -recursive` from repo root — PASS

## Deviations from Plan

None — plan executed exactly as written. `terraform fmt` auto-formatted one inline comment trailing space in `modules/alb/main.tf` (the `idle_timeout` comment); this is expected and non-breaking behavior.

## Threat Mitigations Implemented

Per threat model in the plan:

| Threat ID | Category | Mitigation |
|-----------|----------|------------|
| T-05-05 | Info Disclosure | `aws_lb_listener.http` issues HTTP 301 redirect to HTTPS:443 — all cleartext upgraded before reaching any backend |
| T-05-06 | Tampering | `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` enforces TLS 1.2 minimum + TLS 1.3 support |
| T-05-07 | Tampering | `drop_invalid_header_fields = true` strips non-conformant HTTP headers from reaching tasks |
| T-05-08 | Elevation | Task SG accepting 8069 only from ALB SG (Phase 1, unchanged) — this plan does not weaken that boundary |
| T-05-09 | DoS | `enable_deletion_protection = false` accepted per D-04 lean MVP posture |
| T-05-10 | Info Disclosure | `placeholder.example.com` is not a secret; plainly a non-real domain |

## Known Stubs

None. This plan creates a complete ALB module with all three required resources. The `listener_arn` output is wired to an actual resource attribute. No placeholder or stub values remain in the ALB module files.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes beyond what the plan's threat model covers.

## Self-Check: PASSED

- modules/alb/main.tf — FOUND
- modules/alb/variables.tf — FOUND
- modules/alb/outputs.tf — FOUND
- Makefile — FOUND (contains `tenant_domain=placeholder.example.com`)
- Commit 0f147be — FOUND
- Commit 0f7c4e3 — FOUND
