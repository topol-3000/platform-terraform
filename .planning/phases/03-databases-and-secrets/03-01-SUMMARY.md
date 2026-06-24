---
phase: 03-databases-and-secrets
plan: "01"
subsystem: infra
tags: [terraform, aws, ssm, random_password, secrets, securestring]

# Dependency graph
requires:
  - phase: 01-networking
    provides: name_prefix pattern established; modules/ecs/variables.tf analog for ssm/variables.tf
  - phase: 02-container-platform
    provides: modules/ecr/main.tf analog for header comment and tags convention
provides:
  - modules/ssm fully implemented: random_password + aws_ssm_parameter SecureStrings + outputs
  - Sensitive password outputs (tenant_rds_password, cp_rds_password) for RDS module wiring
  - Non-sensitive name/ARN outputs (6) for provisioner contract
affects:
  - 03-02 (rds-tenant consumes tenant_rds_password output)
  - 03-03 (rds-control-plane consumes cp_rds_password output)
  - 03-05 (envs/prod wiring uses ssm module outputs)

# Tech tracking
tech-stack:
  added:
    - hashicorp/random ~> 3.0 (random_password resource — offline secret generation)
  patterns:
    - random_password -> aws_ssm_parameter SecureString chain (D-01 single secret source)
    - lifecycle { ignore_changes = [value] } on SSM parameters for out-of-band rotation (D-02)
    - sensitive = true on outputs referencing random_password.*.result (T-03-01 mitigation)
    - key_id omitted on aws_ssm_parameter to use default alias/aws/ssm (D-09)
    - No data sources anywhere in module — keeps offline make plan-check gate green (D-03)

key-files:
  created: []
  modified:
    - modules/ssm/main.tf
    - modules/ssm/outputs.tf

key-decisions:
  - "D-01 honored: random_password generates all secrets offline in modules/ssm; result passed to aws_ssm_parameter and exported as sensitive output for RDS wiring — single secret source"
  - "D-02 honored: lifecycle { ignore_changes = [value] } on every aws_ssm_parameter — out-of-band rotation never causes Terraform drift"
  - "D-03 honored: zero data sources in modules/ssm — fully offline, keeps make plan-check gate green"
  - "D-09 honored: key_id omitted on all aws_ssm_parameter resources — uses default alias/aws/ssm AWS-managed key"

patterns-established:
  - "SSM boundary pattern: generate random_password inside modules/ssm; export .result as sensitive output for inter-module wiring; export only .name/.arn for provisioner contract"
  - "Never output aws_ssm_parameter.*.value — always output random_password.*.result with sensitive = true"

requirements-completed:
  - SSM-01

# Metrics
duration: 2min
completed: 2026-06-24
---

# Phase 3 Plan 01: SSM Module Summary

**Three random_password resources generate RDS master passwords and HMAC salt offline; aws_ssm_parameter SecureStrings store them with lifecycle ignore_changes; outputs export sensitive raw values for inter-module wiring and non-sensitive names/ARNs for the provisioner contract.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-24T06:59:22Z
- **Completed:** 2026-06-24T07:01:22Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `modules/ssm/main.tf` fully implemented: 3 random_password + 3 aws_ssm_parameter SecureStrings with lifecycle { ignore_changes = [value] } and Name-only tags
- `modules/ssm/outputs.tf` fully implemented: 2 sensitive pass-through outputs (random_password.*.result) + 6 non-sensitive name/ARN outputs; zero aws_ssm_parameter.*.value references
- `terraform fmt -check` passes on modules/ssm/; all plan acceptance criteria satisfied

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement modules/ssm/variables.tf and modules/ssm/main.tf** - `e962be2` (feat)
2. **Task 2: Implement modules/ssm/outputs.tf** - `f89b579` (feat)

**Plan metadata:** see below (docs commit)

## Files Created/Modified

- `modules/ssm/main.tf` - 3 random_password + 3 aws_ssm_parameter SecureString resources; lifecycle ignore_changes; WHY-style comments; no data sources
- `modules/ssm/outputs.tf` - 2 sensitive password outputs from random_password.*.result + 6 name/ARN outputs; no .value references

## Decisions Made

None - followed plan as specified. All decisions (D-01, D-02, D-03, D-09) were pre-locked in CONTEXT.md and honored exactly.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `modules/ssm` is ready to be consumed by `modules/rds-tenant` (Plan 03-02) and `modules/rds-control-plane` (Plan 03-03)
- Both RDS plans can proceed in parallel (Wave 2) — they consume `module.ssm.tenant_rds_password` and `module.ssm.cp_rds_password` respectively
- No blockers or concerns; all offline plan gate constraints satisfied

## Known Stubs

None - modules/ssm is fully implemented with no placeholder outputs or hardcoded empty values.

## Threat Flags

No new threat surface introduced beyond the plan's threat model. T-03-01 (Information Disclosure via sensitive outputs) is mitigated: sensitive = true on both password outputs, never re-exported to envs/prod/outputs.tf. T-03-02 (SSM value in state) is mitigated-by-infrastructure (AES-256 SSE on S3 state bucket from bootstrap).

---
*Phase: 03-databases-and-secrets*
*Completed: 2026-06-24*

## Self-Check: PASSED

- `modules/ssm/main.tf` — FOUND
- `modules/ssm/outputs.tf` — FOUND
- Task 1 commit `e962be2` — FOUND
- Task 2 commit `f89b579` — FOUND
