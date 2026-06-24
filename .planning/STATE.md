---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Complete the shared AWS baseline
status: executing
last_updated: "2026-06-24T11:13:52.070Z"
last_activity: 2026-06-24 -- Phase 05 execution started
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 15
  completed_plans: 12
  percent: 80
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-23)

**Core value:** `terraform` in `envs/prod` produces a correct, well-formed plan for the shared AWS baseline — every module the provisioner depends on is implemented, wired, and exports the identifiers the `AwsDeploymentAdapter` needs.
**Current focus:** Phase 05 — tls-and-routing

## Current Position

Phase: 05 (tls-and-routing) — EXECUTING
Plan: 1 of 3
Status: Executing Phase 05
Last activity: 2026-06-24 -- Phase 05 execution started

Progress: [░░░░░░░░░░] 0% (0/4 phases complete)

## Performance Metrics

**Velocity:**

- Total plans completed: 12 (Phase 1, previous milestone)
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 2 | - | - |
| 02 | 3 | - | - |
| 03 | 5 | - | - |
| 04 | 2 | - | - |
| 05 | TBD | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- One milestone at a time — networking module was the sole scope of v1.0; v1.1 completes the remaining 10 modules.
- Code-complete verification only — fmt -check + validate + non-empty plan via `make plan-check`; no `terraform apply`, no AWS spend/creds.
- Public subnets only, no NAT gateway (cost) — exposed under the existing `private_subnet_ids` output name so the provisioner contract is unchanged.
- Task SG must accept 8069 only from the ALB SG id (not a CIDR) — sole guard against direct internet exposure of tasks on public subnets.
- SSM implemented in Phase 3 alongside RDS — RDS-01 sources master credentials from SSM; implementing both in the same phase avoids a forward-reference bootstrapping problem.
- Module labels use underscores not hyphens — e.g. `module "rds_tenant"` referenced as `module.rds_tenant.*` (CONCERNS.md fragile area).
- Phase 3 and Phase 4 are independent of each other — both depend only on Phase 1 networking outputs (already wired); may execute in either order.

### Pending Todos

- Pre-declare missing variables before implementing resource bodies (CONCERNS.md): `subnet_ids`/`vpc_id` in `modules/rds-tenant/variables.tf`; `tenant_domain` in `modules/acm/variables.tf` and `modules/route53/variables.tf`; `acm_cert_arn` in `modules/alb/variables.tf`.
- Add `validation` block for `tenant_domain` in acm and route53 modules (CONCERNS.md security concern — guards against empty-string default silently creating invalid resources).

### Blockers/Concerns

None currently blocking. Key concerns to watch during execution:

- RDS SG must accept 5432 only from task SG id (not CIDR) — mirrors the networking SG pattern.
- EFS SG must accept 2049 only from task SG id (not CIDR).
- `multi_az = false` for tenant RDS, `multi_az = true` for control-plane RDS (separate instances).
- ALB `idle_timeout > 60` (Odoo longpoll ~50s).
- SSM params must be `SecureString`; never expose secret values in outputs or state.
- Per-tenant resources (DBs, ECS services, EFS access points, target groups, DNS records) are NOT created here — provisioner adapter handles those at runtime.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260622-opq | Switch prod baseline default region to us-east-1 | 2026-06-22 | 1313d5d | [260622-opq-switch-region-us-east-1](./quick/260622-opq-switch-region-us-east-1/) |

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-06-24T10:15:24.958Z
Stopped at: Phase 5 context gathered
Resume file: .planning/phases/05-tls-and-routing/05-CONTEXT.md
