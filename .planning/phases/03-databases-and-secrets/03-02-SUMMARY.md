---
phase: 03-databases-and-secrets
plan: "02"
subsystem: modules/rds-tenant
tags:
  - rds
  - postgresql
  - security-group
  - terraform
  - databases

dependency_graph:
  requires:
    - "03-01"  # modules/ssm — provides master_password sensitive output
    - "01"     # modules/networking — provides vpc_id, subnet_ids, task_security_group_id
  provides:
    - "modules/rds-tenant — endpoint, identifier, security_group_id, db_resource_id"
  affects:
    - "03-04 (rds-proxy) — consumes identifier and security_group_id"
    - "envs/prod/main.tf — module.rds_tenant wiring (Plan 05)"

tech_stack:
  added:
    - "aws_security_group (rds-tenant SG)"
    - "aws_db_subnet_group"
    - "aws_db_parameter_group (postgres16)"
    - "aws_db_instance (Single-AZ PostgreSQL)"
  patterns:
    - "SG-reference ingress (port 5432 from task SG only — same pattern as networking module port 8069)"
    - "lifecycle { ignore_changes = [password] } for out-of-band rotation (D-02)"
    - "deletion_protection + skip_final_snapshot = false guard (D-08)"
    - "AWS-managed storage encryption via storage_encrypted = true (D-09)"

key_files:
  created: []
  modified:
    - modules/rds-tenant/variables.tf
    - modules/rds-tenant/main.tf
    - modules/rds-tenant/outputs.tf

decisions:
  - "D-02: lifecycle { ignore_changes = [password] } on aws_db_instance.tenant — out-of-band password rotation does not cause Terraform drift"
  - "D-03: no data aws_ssm_parameter source — master password arrives as sensitive variable from modules/ssm, keeping offline make plan-check gate green"
  - "D-07: instance_class=db.t4g.small, storage_type=gp3, allocated_storage=20 with max_allocated_storage=100 autoscaling (all overridable)"
  - "D-08: deletion_protection=true + skip_final_snapshot=false + final_snapshot_identifier on aws_db_instance.tenant"
  - "D-09: storage_encrypted=true with no kms_key_id (default AWS-managed RDS key)"
  - "D-11: all 9 variables pre-declared before implementing resource bodies"

metrics:
  duration: "~2 minutes"
  completed: "2026-06-24"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
---

# Phase 03 Plan 02: rds-tenant module implementation Summary

Single-AZ shared PostgreSQL instance (database-per-tenant) with SG-reference port-5432 ingress from the task SG only, sensitive master password wired from modules/ssm, deletion protection with final snapshot, gp3 storage encryption, and out-of-band rotation lifecycle guard.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Pre-declare all variables in modules/rds-tenant/variables.tf (D-11) | d24ad51 | modules/rds-tenant/variables.tf |
| 2 | Implement modules/rds-tenant/main.tf and modules/rds-tenant/outputs.tf | 1a72b28 | modules/rds-tenant/main.tf, modules/rds-tenant/outputs.tf |

## What Was Built

**modules/rds-tenant/variables.tf** — 9 variables declared (D-11 pre-declaration):
- Required (no default): `name_prefix`, `subnet_ids`, `vpc_id`, `task_security_group_id`, `master_password` (sensitive=true)
- Optional with prod defaults (D-07): `instance_class=db.t4g.small`, `engine_version=16`, `allocated_storage=20`, `max_allocated_storage=100`

**modules/rds-tenant/main.tf** — 4 resources:
1. `aws_security_group.rds_tenant` — ingress port 5432 using `security_groups=[var.task_security_group_id]` only (no cidr_blocks on 5432 rule — T-03-05 mitigation)
2. `aws_db_subnet_group.tenant` — subnet group for the shared instance
3. `aws_db_parameter_group.tenant` — postgres16 family with `create_before_destroy = true`
4. `aws_db_instance.tenant` — Single-AZ (`multi_az=false`), `storage_encrypted=true`, `deletion_protection=true`, `skip_final_snapshot=false`, `publicly_accessible=false`, `lifecycle { ignore_changes = [password] }`

**modules/rds-tenant/outputs.tf** — 4 outputs:
- `endpoint` — feeds Plan 05 wiring and provisioner `aws_shared_rds_endpoint`
- `identifier` — feeds Plan 04 (rds-proxy) `db_instance_identifier`
- `security_group_id` — feeds Plan 04 (rds-proxy) SG ingress wiring
- `db_resource_id` — reserved for future IAM authentication

## Verification Results

- 9 variables declared including `vpc_id` (D-11 satisfied)
- `master_password` has `sensitive = true`
- `security_groups = [var.task_security_group_id]` on 5432 ingress; no `cidr_blocks` on that rule (T-03-05 satisfied)
- `multi_az = false` (D-07 satisfied)
- `storage_encrypted = true` (D-09 satisfied)
- `deletion_protection = true` + `skip_final_snapshot = false` (D-08 satisfied)
- `lifecycle { ignore_changes = [password] }` (D-02 satisfied)
- No `data` source blocks anywhere in main.tf (D-03 satisfied)
- All 4 outputs present: endpoint, identifier, security_group_id, db_resource_id
- `terraform fmt -check -recursive modules/rds-tenant/` passes

## Deviations from Plan

None — plan executed exactly as written. `terraform fmt` was applied after writing main.tf (attribute alignment adjustment — standard formatter pass, not a logic deviation).

## Known Stubs

None — all resources are fully implemented. The module is not yet wired into `envs/prod/main.tf` (that is Plan 05's responsibility).

## Threat Flags

No new threat surface beyond what was already documented in the plan's threat model. All four threat register entries (T-03-04 through T-03-07) are mitigated by the implementation.

## Self-Check: PASSED

- [x] modules/rds-tenant/variables.tf exists with 9 variables
- [x] modules/rds-tenant/main.tf exists with 4 resources, no data sources
- [x] modules/rds-tenant/outputs.tf exists with 4 outputs
- [x] Task 1 commit d24ad51 confirmed in git log
- [x] Task 2 commit 1a72b28 confirmed in git log
- [x] terraform fmt -check passes
