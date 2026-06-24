---
phase: 03-databases-and-secrets
plan: "04"
subsystem: database
tags: [terraform, rds-proxy, aws-db-proxy, secrets-manager, iam, count-gate]

# Dependency graph
requires:
  - phase: 03-databases-and-secrets/03-02
    provides: rds-tenant module (identifier and security_group_id outputs used by rds-proxy wiring)
provides:
  - modules/rds-proxy fully implemented: 8 count-gated resources behind enable_rds_proxy flag (default false)
  - try() guard on endpoint output ensures envs/prod wiring resolves to null when flag is off
  - Secrets Manager secret as sole sanctioned SSM exception (D-05)
affects:
  - 03-05 (envs/prod wiring — passes module.rds_tenant.identifier as db_instance_identifier and enable_rds_proxy flag)

# Tech tracking
tech-stack:
  added: [aws_secretsmanager_secret, aws_secretsmanager_secret_version, aws_iam_role, aws_iam_role_policy, aws_db_proxy, aws_db_proxy_default_target_group, aws_db_proxy_target]
  patterns: [count-gate pattern (count = var.enable_rds_proxy ? 1 : 0), try() guard for count-gated output, SG-reference ingress on 5432, IAM role scoped to single secret ARN]

key-files:
  created: []
  modified:
    - modules/rds-proxy/variables.tf
    - modules/rds-proxy/main.tf
    - modules/rds-proxy/outputs.tf

key-decisions:
  - "D-04 honored: all 8 proxy resources count-gated behind enable_rds_proxy (default false) — 0 proxy resources in the default plan"
  - "D-05 honored: Secrets Manager secret materialises only when enable_rds_proxy = true; sole SSM exception because RDS Proxy auth cannot use SSM directly"
  - "D-06 satisfied: try(aws_db_proxy.this[0].endpoint, null) — canonical form, not length() ternary; output resolves to null when flag is off"
  - "D-11 honored: all variables pre-declared before resource implementation; safe empty/false defaults allow the module call to omit flag-dependent vars when disabled"

patterns-established:
  - "Count-gate pattern: count = var.enable_rds_proxy ? 1 : 0 on every resource in the module — missing count on any resource causes plan error when flag is off"
  - "try() guard for count-gated outputs: try(resource[0].attr, null) is canonical; do not use length() ternary"
  - "Secrets Manager as sole exception: first and only aws_secretsmanager_secret in the repo; justified only by RDS Proxy auth requirement"
  - "IAM policy Resource scoped to single secret ARN: never use wildcard (T-03-13)"
  - "Proxy SG ingress uses security_groups = [var.task_security_group_id] — no CIDR on 5432 (T-03-14)"

requirements-completed: [RDS-02]

# Metrics
duration: 14min
completed: 2026-06-24
---

# Phase 03 Plan 04: RDS Proxy Summary

**RDS Proxy module fully implemented with 8 count-gated resources behind enable_rds_proxy flag (default false), Secrets Manager auth secret as sole SSM exception, and try() endpoint output guard for zero-cost wiring when proxy is disabled.**

## Performance

- **Duration:** ~14 min
- **Started:** 2026-06-24T06:57:00Z
- **Completed:** 2026-06-24T07:11:54Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Declared all 8 required variables in modules/rds-proxy/variables.tf per D-11, with enable_rds_proxy (bool, default false) as the core gate and master_password marked sensitive
- Implemented 8 resources in modules/rds-proxy/main.tf — each gated with count = var.enable_rds_proxy ? 1 : 0 — covering the full proxy resource set: Secrets Manager secret + version, IAM role + policy, SG, proxy, default target group, proxy target
- Implemented modules/rds-proxy/outputs.tf with try(aws_db_proxy.this[0].endpoint, null) so envs/prod wiring resolves to null rather than failing when the flag is off
- All three files pass terraform fmt -check

## Task Commits

1. **Task 1: Pre-declare all variables in modules/rds-proxy/variables.tf (D-11)** - `1466d08` (feat)
2. **Task 2: Implement modules/rds-proxy/main.tf and modules/rds-proxy/outputs.tf** - `dd6fdfa` (feat)

## Files Created/Modified

- `modules/rds-proxy/variables.tf` - 8 variables: name_prefix, enable_rds_proxy (bool, default false), db_instance_identifier, subnet_ids, vpc_id, task_security_group_id, master_username, master_password (sensitive)
- `modules/rds-proxy/main.tf` - 8 count-gated resources; Secrets Manager secret, IAM role + policy scoped to single secret ARN, SG with SG-reference ingress, aws_db_proxy (engine_family=POSTGRESQL), default target group (connection pool config), proxy target
- `modules/rds-proxy/outputs.tf` - Single endpoint output using try() guard

## Decisions Made

- Honored D-04: all 8 resources use count = var.enable_rds_proxy ? 1 : 0; default plan shows 0 proxy resources
- Honored D-05: aws_secretsmanager_secret.proxy_auth is the sole Secrets Manager resource in the repo; materialized only when flag is true; WHY-comment documents the exception
- Honored D-06: try() form used for the endpoint output (not length() ternary) — canonical per RESEARCH.md
- Honored D-11: variables pre-declared first (Task 1), resources implemented second (Task 2)
- T-03-13 mitigated: IAM policy Resource restricted to [aws_secretsmanager_secret.proxy_auth[0].arn], not a wildcard
- T-03-14 mitigated: proxy SG uses security_groups = [var.task_security_group_id] on port 5432; no CIDR ingress

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- modules/rds-proxy is fully implemented; Plan 05 (envs/prod wiring) can pass module.rds_tenant.identifier as db_instance_identifier and the enable_rds_proxy flag
- The rds_proxy module call in envs/prod/main.tf stub is ready to be uncommented and wired
- The rds_proxy_endpoint output in envs/prod/outputs.tf stub is ready to be uncommented

---
*Phase: 03-databases-and-secrets*
*Completed: 2026-06-24*
