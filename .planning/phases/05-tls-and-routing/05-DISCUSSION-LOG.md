# Phase 5: TLS and routing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-24
**Phase:** 5-tls-and-routing
**Areas discussed:** ALB listener topology, ACM validation depth, Fleet-wide DNS, ALB cost/hardening toggles

---

## ALB listener topology

| Option | Description | Selected |
|--------|-------------|----------|
| 80→443 redirect + 503 default | HTTP:80 listener 301-redirects to HTTPS; HTTPS:443 default_action is fixed-response 503. SG already allows 80/443. | ✓ |
| 443-only + 503 default | No port-80 listener; only HTTPS:443 with a 503 default. Plain-HTTP clients get connection-refused. | |
| 80→443 redirect + 404 default | Same redirect, but 443 default returns 404 instead of 503. | |

**User's choice:** 80→443 redirect + 503 default
**Notes:** 503 ("no tenant provisioned yet") chosen over 404 as the more accurate semantic for an unrouted host that the adapter will later attach a host rule to. → D-01.

---

## ACM validation depth

| Option | Description | Selected |
|--------|-------------|----------|
| Bare cert, no validation chain | `aws_acm_certificate` with `validation_method=DNS` only; no validation records, no `aws_acm_certificate_validation`. Keeps acm/route53 decoupled. | ✓ |
| Full validation chain | Wire DNS validation records + `aws_acm_certificate_validation`; couples acm→route53 and adds an apply-only no-op resource. | |

**User's choice:** Bare cert, no validation chain
**Notes:** Verification is code-complete only/offline, so the validation resource is a no-op under the gate; bare cert keeps the modules decoupled (matches the stub where acm takes no zone id). Full chain deferred to a real apply. → D-02.

---

## Fleet-wide DNS

| Option | Description | Selected |
|--------|-------------|----------|
| Empty zone only | route53 declares only the hosted zone (exports `hosted_zone_id`); adapter owns all records. | ✓ |
| Add wildcard *.{domain} ALIAS→ALB | Also create a fleet-wide `*.{tenant_domain}` ALIAS A-record → ALB; couples route53→alb. | |

**User's choice:** Empty zone only
**Notes:** Keeps route53 decoupled from alb and matches the SEED-001 route53 stub note (adapter creates records at provision time). Wildcard ALIAS deferred. → D-03.

---

## ALB cost/hardening toggles

| Option | Description | Selected |
|--------|-------------|----------|
| Lean: logs off, no deletion protection | No access-log S3 bucket; `deletion_protection=false`; keep http2 + `drop_invalid_header_fields=true` (free hardening). | ✓ |
| Enable access logs (S3 bucket) | Provision an S3 bucket + policy and enable ALB access logs; adds resources/cost + apply-time bucket-policy dependency. | |
| You decide | Follow the established cost-lean pattern at planner's discretion. | |

**User's choice:** Lean: logs off, no deletion protection
**Notes:** Consistent with the Phase 3/4 cost-lean MVP pattern (proxy-off, backups-off). Access logs framed as deferred hardening, not rejected. → D-04.

---

## Claude's Discretion

- ALB wiring inputs (thread public subnets + ALB SG from networking into the alb module; declare matching variables; `internal=false`, `load_balancer_type="application"`).
- The exact `tenant_domain` validation regex (reused in acm + route53).
- The fixed-response 503 body/content-type (only the status matters).
- Whether to also export `alb_arn`/`alb_dns_name`/`cert_domain`/`zone_name_servers` (only the three contract outputs are required).
- route53 `force_destroy` setting.

## Deferred Ideas

- ACM DNS validation chain (validation records + `aws_acm_certificate_validation`) — needed for a real apply, no-op under the offline gate.
- Fleet-wide wildcard `*.{tenant_domain}` ALIAS → ALB record.
- ALB access logs (S3 bucket + policy + `access_logs` block) — deferred hardening item.
- `healthCheckGracePeriod >= 240s` + per-tenant target groups / host rules / DNS records — adapter-owned at runtime, not Terraform's job this milestone.
