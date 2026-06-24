---
phase: 03-databases-and-secrets
plan: "03"
subsystem: database
tags: [terraform, rds, postgresql, multi-az, security-group, aws]

# Dependency graph
requires:
  - phase: 03-01
    provides: cp_rds_password sensitive output from modules/ssm (wired in Plan 05)
  - phase: 01-networking
    provides: vpc_id, private_subnet_ids, task_security_group_id (consumed as module inputs)
provides:
  - modules/rds-control-plane fully implemented: Multi-AZ PostgreSQL instance isolated from rds-tenant
  - endpoint output for envs/prod wiring in Plan 05
  - security_group_id output for future cross-module references
affects:
  - 03-05 (envs/prod wiring — uncomments rds_control_plane module call)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Multi-AZ RDS instance with deletion_protection + skip_final_snapshot=false (D-08)
    - SG-reference ingress on port 5432 from task SG (no cidr_blocks on 5432 rule)
    - lifecycle.ignore_changes=[password] for out-of-band rotation without drift (D-02)
    - Separate cp-prefixed resources (SG, subnet group, param group, identifier) — SEED-001 blast-radius isolation

key-files:
  created: []
  modified:
    - modules/rds-control-plane/variables.tf
    - modules/rds-control-plane/main.tf
    - modules/rds-control-plane/outputs.tf

key-decisions:
  - "multi_az = true (not false) — control-plane requires 99.9% SLA for provisioner operational data; tenant RDS uses Single-AZ (cost)"
  - "db_name = provisioner (not odoo_shared) — control-plane holds provisioner data, not tenant data; different schema requirements"
  - "All resource labels use cp/control_plane suffix — strict SEED-001 isolation; no shared names, subnet groups, SGs, or identifiers with rds-tenant"
  - "storage_encrypted = true without kms_key_id — AWS-managed RDS key (D-09); customer CMK deferred post-MVP"

patterns-established:
  - "Control-plane RDS: identical structure to rds-tenant with multi_az=true and cp/* resource labels"
  - "SG-reference ingress: security_groups=[var.task_security_group_id] with no cidr_blocks on 5432 rule"
  - "Deletion guard: deletion_protection=true + skip_final_snapshot=false + final_snapshot_identifier (mirrors bootstrap S3 ethos)"

requirements-completed: [RDS-03]

# Metrics
duration: 2min
completed: 2026-06-24
---

# Phase 03 Plan 03: RDS Control-Plane Summary

**Multi-AZ PostgreSQL control-plane instance for provisioner data: isolated SG + subnet group + parameter group with deletion_protection, storage encryption, and SG-reference port-5432 ingress**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-24T07:04:40Z
- **Completed:** 2026-06-24T07:07:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Pre-declared 9 variables in variables.tf matching the rds-tenant interface (D-11), including sensitive master_password and list(string) subnet_ids
- Implemented aws_security_group.cp_rds with SG-reference-only ingress on port 5432 (security_groups=[var.task_security_group_id], no cidr_blocks — T-03-09 mitigated)
- Implemented aws_db_instance.control_plane with multi_az=true, storage_encrypted=true, deletion_protection=true, skip_final_snapshot=false, db_name="provisioner", lifecycle.ignore_changes=[password] — all SEED-001 isolation and D-02/D-07/D-08/D-09 requirements met
- All resource labels use cp/control_plane suffix; zero overlap with rds-tenant names (T-03-10 mitigated)

## Task Commits

Each task was committed atomically:

1. **Task 1: Pre-declare all variables (D-11)** - `041c8fc` (feat)
2. **Task 2: Implement main.tf and outputs.tf** - `1f48932` (feat)

## Files Created/Modified

- `modules/rds-control-plane/variables.tf` - 9 variables: name_prefix, subnet_ids, vpc_id, task_security_group_id, master_password (sensitive), instance_class, engine_version, allocated_storage, max_allocated_storage
- `modules/rds-control-plane/main.tf` - aws_security_group.cp_rds + aws_db_subnet_group.cp + aws_db_parameter_group.cp + aws_db_instance.control_plane (Multi-AZ)
- `modules/rds-control-plane/outputs.tf` - endpoint + security_group_id outputs

## Decisions Made

- Used `db_name = "provisioner"` (not `"odoo_shared"`) — control-plane holds provisioner operational data; distinct schema from the tenant shared database
- All cp_rds resources isolated from rds-tenant by name, subnet group, SG, and identifier — SEED-001 blast-radius isolation enforced at naming level
- No kms_key_id on aws_db_instance.control_plane — AWS-managed RDS key satisfies D-09 at MVP; customer CMK deferred

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. This plan is code-complete only (no terraform apply).

## Next Phase Readiness

- modules/rds-control-plane is fully implemented and ready for wiring in Plan 05 (envs/prod)
- endpoint output is available as module.rds_control_plane.endpoint for envs/prod/outputs.tf
- security_group_id output available if future modules need SG reference (e.g., for VPC endpoint or cross-SG rules)
- terraform fmt -check passes on modules/rds-control-plane/

---
*Phase: 03-databases-and-secrets*
*Completed: 2026-06-24*
