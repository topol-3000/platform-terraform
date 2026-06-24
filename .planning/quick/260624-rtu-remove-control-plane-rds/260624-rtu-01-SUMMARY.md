---
phase: quick-260624-rtu
plan: 01
subsystem: infra
tags: [terraform, rds, ssm, control-plane, module-removal]

requires: []
provides:
  - modules/rds-control-plane/ deleted (module directory gone)
  - modules/ssm/ manages tenant_rds and hmac_salt credentials only
  - envs/prod/main.tf wires 10 modules (no rds_control_plane block)
  - envs/prod/outputs.tf exports 12 outputs (no control_plane_rds_endpoint)
affects: [provisioner AwsDeploymentAdapter — control_plane_rds_endpoint removed from contract]

tech-stack:
  added: []
  patterns:
    - "Control-plane DB ownership moved outside this repo — provisioner owns its own operational DB"

key-files:
  created: []
  modified:
    - modules/ssm/main.tf
    - modules/ssm/outputs.tf
    - envs/prod/main.tf
    - envs/prod/outputs.tf
    - README.md
  deleted:
    - modules/rds-control-plane/main.tf
    - modules/rds-control-plane/variables.tf
    - modules/rds-control-plane/outputs.tf

key-decisions:
  - "Control-plane RDS removed from shared baseline — provisioner hosts its own operational DB independently"
  - "SSM module trimmed to 2 random_password + 2 aws_ssm_parameter resources (tenant_rds + hmac_salt only)"
  - "envs/prod/outputs.tf provisioner contract now has 12 outputs, no control_plane_rds_endpoint"

requirements-completed: [remove-control-plane-rds]

duration: 8min
completed: 2026-06-24
---

# Quick Task 260624-rtu-01: Remove rds-control-plane Module Summary

**Deleted modules/rds-control-plane/, stripped cp_rds SSM resources, and removed all wiring — `make plan-check` passes clean with 10 modules and no control-plane references.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-06-24T20:00:00Z
- **Completed:** 2026-06-24T20:08:37Z
- **Tasks:** 3
- **Files modified:** 5 (+ 3 deleted)

## Accomplishments

- Deleted the entire `modules/rds-control-plane/` directory (3 files)
- Removed `random_password.cp_rds` and `aws_ssm_parameter.cp_rds_password` from `modules/ssm/main.tf`
- Removed `cp_rds_password`, `cp_rds_password_name`, `cp_rds_password_arn` outputs from `modules/ssm/outputs.tf`
- Removed `module "rds_control_plane"` block from `envs/prod/main.tf`
- Removed `output "control_plane_rds_endpoint"` from `envs/prod/outputs.tf`
- Updated README: layout tree, outputs table, module status table, module count (11 → 10), rds_instance_class note
- `make plan-check` exits 0: fmt-check clean, validate clean, non-empty plan with no control-plane references

## Task Commits

1. **Task 1: Remove control-plane Terraform resources and module wiring** - `d01b906` (refactor)
2. **Task 2: Update README — drop all control-plane references** - `1545690` (docs)
3. **Task 3: Run offline plan-check gate** - verification only, no commit required

## Files Created/Modified

- `modules/rds-control-plane/main.tf` - DELETED
- `modules/rds-control-plane/variables.tf` - DELETED
- `modules/rds-control-plane/outputs.tf` - DELETED
- `modules/ssm/main.tf` - Removed cp_rds random_password and aws_ssm_parameter blocks
- `modules/ssm/outputs.tf` - Removed cp_rds_password, cp_rds_password_name, cp_rds_password_arn outputs; updated header comment
- `envs/prod/main.tf` - Removed module "rds_control_plane" block (13 lines)
- `envs/prod/outputs.tf` - Removed output "control_plane_rds_endpoint" block (4 lines)
- `README.md` - Removed layout tree entry, outputs table row, module status row; updated count 11→10; updated rds_instance_class note

## Decisions Made

- The provisioner service owns its own operational database — this repo provisions only tenant-facing shared infrastructure. Removing the control-plane RDS from this repo is a clean boundary enforcement.
- No `rds_proxy_endpoint` output was removed — the proxy is still present (gated by `enable_rds_proxy`), only the control-plane endpoint was dropped.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None — no stub patterns introduced.

## Threat Flags

None — deletion of a module reduces attack surface; no new network endpoints or auth paths introduced.

## Self-Check

- `test ! -d modules/rds-control-plane` — PASS
- `grep -r "rds_control_plane|cp_rds|control_plane_rds" modules/ssm/ envs/prod/` — PASS (no matches)
- `grep -n "rds-control-plane|control_plane_rds" README.md` — PASS (no matches)
- `make plan-check` — PASS (exits 0, non-empty plan, no control-plane resources)

## Self-Check: PASSED

---
*Quick Task: 260624-rtu*
*Completed: 2026-06-24*
