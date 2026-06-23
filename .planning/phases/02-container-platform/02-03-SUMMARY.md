---
phase: 02-container-platform
plan: "03"
subsystem: infra
tags: [terraform, ecr, ecs, wiring, envs-prod, offline-gate]

# Dependency graph
requires:
  - phase: 02-container-platform
    plan: "01"
    provides: "modules/ecr: image_uri output"
  - phase: 02-container-platform
    plan: "02"
    provides: "modules/ecs: cluster_arn output"
provides:
  - "envs/prod/main.tf: live module \"ecr\" (step 3) and module \"ecs\" (step 4) calls"
  - "envs/prod/outputs.tf: live ecr_image_uri (= module.ecr.image_uri) and ecs_cluster_arn (= module.ecs.cluster_arn) contract outputs"
affects: [provisioner AwsDeploymentAdapter — consumes ecr_image_uri and ecs_cluster_arn]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Module wiring pattern: uncomment + wire root module calls; all wiring stays in envs/prod/main.tf, never cross-module"
    - "Contract output pattern: description ends with -> provisioner `<setting_name>` per CONVENTIONS.md"

key-files:
  created: []
  modified:
    - envs/prod/main.tf
    - envs/prod/outputs.tf

key-decisions:
  - "D-06 honored: module \"ecr\" (step 3) and module \"ecs\" (step 4) uncommented and wired via name_prefix = local.name_prefix only"
  - "D-07 honored: providers.tf and backend.tf untouched; gate_override.tf written transiently by Makefile trap, removed after gate run"
  - "Step-3 banner text updated from pull-through/GHCR wording to managed-repository wording (D-01 consistency)"
  - "ecr_image_uri description rewritten from stale 'ECR pull-through image URI' to 'ECR repository URL for odoo-core -> provisioner `aws_ecr_image`.' (D-01/D-06)"
  - "VER-01 satisfied: make plan-check exits 0 with 13 resources (was 9 in Phase 1), including aws_ecr_repository and aws_ecs_cluster"

# Metrics
duration: "8min"
completed: "2026-06-23T10:39:00Z"
tasks_completed: 2
tasks_total: 2
files_modified: 2
---

# Phase 02 Plan 03: ECR/ECS Wiring Summary

Wire `modules/ecr` (step 3) and `modules/ecs` (step 4) into `envs/prod`, uncomment the `ecr_image_uri` and `ecs_cluster_arn` contract outputs, and confirm `make plan-check` stays green with 13 resources including `aws_ecr_repository` and `aws_ecs_cluster` (VER-01 satisfied, Phase 2 code-complete).

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-23T10:31:00Z
- **Completed:** 2026-06-23T10:39:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Uncommented `module "ecr"` (step 3) and `module "ecs"` (step 4) in `envs/prod/main.tf`. Both calls take only `name_prefix = local.name_prefix`; neither references `module.networking.*` (ECR/ECS consume no networking outputs).
- Updated the step-3 banner comment from the stale "ECR pull-through cache (odoo-core image from GHCR)" to "Managed ECR repository (odoo-core image)" — consistent with D-01.
- Uncommented `ecs_cluster_arn` output (`value = module.ecs.cluster_arn`) — description was already correct.
- Uncommented `ecr_image_uri` output (`value = module.ecr.image_uri`) and rewrote its description from the stale "ECR pull-through image URI -> provisioner `aws_ecr_image`." to "ECR repository URL for odoo-core -> provisioner `aws_ecr_image`." (D-01/D-06).
- Confirmed `make plan-check` exits 0: `terraform fmt -check -recursive` passes, `terraform validate` passes, `terraform plan` produces a non-empty plan with 13 resources (Phase 1 had 9; the 4 new resources are `aws_ecr_repository.odoo_core`, `aws_ecr_lifecycle_policy.odoo_core`, `aws_ecs_cluster.main`, `aws_ecs_cluster_capacity_providers.main`).

## Task Commits

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Uncomment and wire ecr/ecs module calls and contract outputs | 5b88512 | envs/prod/main.tf, envs/prod/outputs.tf |
| 2 | Run offline plan-check gate (verify ECR + ECS in non-empty plan) | — (no code changes) | — |

## Files Created/Modified

- `envs/prod/main.tf` — Uncommented `module "ecr"` (step 3) and `module "ecs"` (step 4); updated step-3 banner wording.
- `envs/prod/outputs.tf` — Uncommented `ecs_cluster_arn` and `ecr_image_uri`; rewrote `ecr_image_uri` description to managed-repository wording.

## Decisions Made

- Honored D-06: both module calls are uncommented, each taking only `name_prefix = local.name_prefix`. Step-3 banner updated to "Managed ECR repository (odoo-core image)" for consistency with D-01.
- Honored D-07: `providers.tf` and `backend.tf` are untouched. The `gate_override.tf` is written transiently by the Makefile trap and cleaned up after each gate run.
- `ecr_image_uri` description rewritten to remove all "pull-through" wording per the plan's acceptance check (`! grep -iq 'pull-through' envs/prod/outputs.tf`).
- `make plan-check` gate confirms Phase 2 is code-complete (VER-01): 13 resources to add (networking 9 + ECR repo + ECR lifecycle policy + ECS cluster + ECS capacity-providers association = 13). Plan outputs include `ecr_image_uri` and `ecs_cluster_arn`.

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria met on first implementation pass.

## Threat Surface Scan

No new trust boundaries introduced. Both new outputs (`ecr_image_uri`, `ecs_cluster_arn`) are non-secret identifiers (repository URL, cluster ARN) — consistent with T-02-09 accept disposition. Confirmed `gate_override.tf` is absent from `envs/prod/` after gate run (T-02-08 mitigation via Makefile trap verified).

## Known Stubs

None. All outputs resolve to live module attributes. No placeholder text or hardcoded empty values.

## Self-Check

- [x] `envs/prod/main.tf` contains `module "ecr"` and `module "ecs"` (uncommented)
- [x] `envs/prod/outputs.tf` contains `output "ecr_image_uri"` (value = module.ecr.image_uri) and `output "ecs_cluster_arn"` (value = module.ecs.cluster_arn)
- [x] No "pull-through" in `envs/prod/outputs.tf`
- [x] No "GHCR" in `envs/prod/main.tf` step-3 banner
- [x] Commit `5b88512` exists
- [x] `make plan-check` exits 0 with 13 resources, including `aws_ecr_repository` and `aws_ecs_cluster`
- [x] No `gate_override.tf` left in `envs/prod/`

## Self-Check: PASSED

---
*Phase: 02-container-platform*
*Completed: 2026-06-23*
