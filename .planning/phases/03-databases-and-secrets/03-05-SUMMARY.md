---
phase: 03-databases-and-secrets
plan: 05
subsystem: infra
tags: [terraform, rds, ssm, postgres, secrets, envs-prod, wiring]

# Dependency graph
requires:
  - phase: 03-01
    provides: modules/ssm — random_password → aws_ssm_parameter SecureStrings; sensitive outputs tenant_rds_password, cp_rds_password; non-sensitive name/ARN outputs
  - phase: 03-02
    provides: modules/rds-tenant — aws_db_instance (Single-AZ), subnet group, parameter group, security group; outputs endpoint, identifier, security_group_id
  - phase: 03-03
    provides: modules/rds-control-plane — aws_db_instance (Multi-AZ), subnet group, parameter group, security group; outputs endpoint, security_group_id
  - phase: 03-04
    provides: modules/rds-proxy — count-gated aws_db_proxy; try()-guarded endpoint output; Secrets Manager auth secret
  - phase: 01-networking
    provides: module.networking outputs — private_subnet_ids, vpc_id, task_security_group_id consumed by all four wired modules
provides:
  - envs/prod wired with ssm, rds_tenant, rds_proxy, rds_control_plane module calls (underscore labels, D-10)
  - hashicorp/random ~> 3.0 in required_providers (L-5 landmine fix)
  - enable_rds_proxy (bool, false) + 4 rds sizing variables in variables.tf
  - Three provisioner contract outputs active: tenant_rds_endpoint, rds_proxy_endpoint, control_plane_rds_endpoint
  - make plan-check green: 27 resources (13 Phase 2 + 14 Phase 3), 3 SSM SecureStrings, 0 proxy resources
affects:
  - phase 04 (efs/acm/alb/route53) — will uncomment remaining stubs in same envs/prod/main.tf file
  - provisioner AwsDeploymentAdapter — three new outputs (tenant_rds_endpoint, rds_proxy_endpoint, control_plane_rds_endpoint) complete Phase 3 contract

# Tech tracking
tech-stack:
  added: [hashicorp/random ~> 3.0 (random_password for SSM SecureStrings)]
  patterns:
    - SSM-first wiring: module ssm declared before rds modules so sensitive outputs are available as inputs
    - Sensitive pass-through: module.ssm.tenant_rds_password flows to rds_tenant.master_password in-memory only; never surfaces in envs/prod/outputs.tf
    - enable_rds_proxy flag: default false; all proxy resources count-gated; try() guards endpoint output
    - Underscore module labels: module "rds_tenant" not "rds-tenant" (D-10; hyphen would break all output references)

key-files:
  created: []
  modified:
    - envs/prod/versions.tf
    - envs/prod/variables.tf
    - envs/prod/main.tf
    - envs/prod/outputs.tf

key-decisions:
  - "D-10 enforced: underscore module labels (rds_tenant, rds_proxy, rds_control_plane) match existing commented output references in outputs.tf"
  - "D-12 enforced: make plan-check is the phase gate (fmt-check + validate + non-empty plan); no live-call data sources, no skip_* flags in providers.tf"
  - "Sensitive RDS passwords not exposed in provisioner contract: only endpoint strings cross the envs/prod/outputs.tf boundary (T-03-16 mitigation)"
  - "Worktree rebased onto main before gate run to access Phase 3 module implementations from Plans 01-04"

patterns-established:
  - "SSM-first pattern: declare ssm module before any rds module in envs/prod/main.tf so password outputs are available as inputs"
  - "Module wiring order in comments: section 5 (Databases and secrets) replaces both old section 5 (Databases) and the ssm portion of old section 6"

requirements-completed: [RDS-04, SSM-02]

# Metrics
duration: 25min
completed: 2026-06-24
---

# Phase 3 Plan 05: Env Wiring and Plan Gate Summary

**Four Phase 3 modules (ssm, rds_tenant, rds_proxy, rds_control_plane) wired into envs/prod with underscore labels, sensitive password pass-through, and make plan-check green at 27 resources including 2 RDS instances and 3 SSM SecureStrings**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-24T07:00:00Z
- **Completed:** 2026-06-24T07:25:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `hashicorp/random ~> 3.0` to `required_providers` (L-5 landmine fix — random_password in modules/ssm requires it at terraform init time)
- Declared `enable_rds_proxy` (bool, default false) and four `rds_*` sizing variables in `envs/prod/variables.tf`
- Uncommented and fully wired all four Phase 3 module calls in `envs/prod/main.tf` with underscore labels (D-10), SSM-first ordering, and correct sensitive password pass-through (`module.ssm.tenant_rds_password` → `rds_tenant.master_password`, `module.ssm.cp_rds_password` → `rds_control_plane.master_password`)
- Activated three provisioner contract outputs in `envs/prod/outputs.tf`: `tenant_rds_endpoint`, `rds_proxy_endpoint`, `control_plane_rds_endpoint`; sensitive password values explicitly excluded (T-03-16 mitigation)
- `make plan-check` exits 0: fmt-check clean, validate "Success!", plan shows 27 resources to add (14 new vs Phase 2 baseline of 13)

## Task Commits

Each task was committed atomically:

1. **Task 1: Update envs/prod versions.tf, variables.tf, main.tf, outputs.tf** — `4b3282d` (feat)
2. **Task 2: make plan-check gate** — no separate commit (verification only; no file changes)

**Plan metadata:** see self-check commit below

## Files Created/Modified

- `envs/prod/versions.tf` — added `random = { source = "hashicorp/random", version = "~> 3.0" }` inside required_providers
- `envs/prod/variables.tf` — appended `enable_rds_proxy` (bool, false) + `rds_instance_class`, `rds_engine_version`, `rds_allocated_storage`, `rds_max_allocated_storage`
- `envs/prod/main.tf` — replaced commented database stubs with fully wired module ssm, rds_tenant, rds_proxy, rds_control_plane calls; removed commented ssm from section 6
- `envs/prod/outputs.tf` — uncommented `tenant_rds_endpoint` and `rds_proxy_endpoint` stubs; added new `control_plane_rds_endpoint` output

## Decisions Made

- SSM module must be declared first in the databases+secrets section so `module.ssm.tenant_rds_password` and `module.ssm.cp_rds_password` are available as inputs to the rds modules (Terraform DAG dependency)
- Rebase of the worktree branch onto main was required before plan-check: the worktree was spawned from Phase 2 history (`23d2d66`) and was missing Phase 3 Plans 01-04 module implementations that live on main (`82cd16f`)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Rebased worktree onto main to include Phase 3 module implementations**

- **Found during:** Task 2 (make plan-check)
- **Issue:** `terraform validate` failed with "Unsupported argument" for all module inputs (subnet_ids, vpc_id, task_security_group_id, master_password, etc.) because the worktree was based on Phase 2 history and lacked the module variable declarations added by Plans 01-04
- **Fix:** `git rebase main` from inside the worktree — rebased the single Task 1 commit cleanly onto `82cd16f` (the Phase 3 wave 3 tracking commit that includes all Plan 01-04 work). No conflicts. Task 1 commit hash changed from `d5aaa99` to `4b3282d` (same content, new base)
- **Files modified:** none (rebase operation only)
- **Verification:** make plan-check exits 0 after rebase with all module variables resolved
- **Committed in:** rebase rewrote Task 1 commit to `4b3282d`

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Required to unblock the plan-check gate. No scope creep. Task 1 content unchanged.

## Issues Encountered

- First `make plan-check` run failed with `terraform validate` "Unsupported argument" errors — diagnosed as worktree spawned from Phase 2 base missing Phase 3 module implementations. Resolved by rebasing onto main.

## User Setup Required

None - no external service configuration required.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced by this plan. The only changes are wiring the already-implemented modules into envs/prod/main.tf and activating outputs. The sensitive password boundary (T-03-16) was explicitly checked: `grep "module.ssm.tenant_rds_password" envs/prod/outputs.tf` returns 0 matches.

## Known Stubs

None — all four wired modules are fully implemented (Plans 01-04). The `rds_proxy_endpoint` output returns `null` when `enable_rds_proxy = false` by design (try() guard in modules/rds-proxy/outputs.tf), which is intentional and documented.

## Next Phase Readiness

- Phase 3 is complete: all databases and secrets modules implemented and wired; make plan-check green at 27 resources
- Phase 4 (efs/acm/alb/route53) can proceed: those module stubs in `envs/prod/main.tf` section 6 remain commented and ready to be expanded
- The provisioner contract for Phase 3 is complete: `tenant_rds_endpoint`, `rds_proxy_endpoint`, `control_plane_rds_endpoint` are live in `envs/prod/outputs.tf`

## Self-Check

Checking created/modified files and commits:

- [x] `envs/prod/versions.tf` — contains `hashicorp/random`
- [x] `envs/prod/variables.tf` — contains `enable_rds_proxy`
- [x] `envs/prod/main.tf` — contains `module "ssm"`, `module "rds_tenant"`, `module "rds_proxy"`, `module "rds_control_plane"`
- [x] `envs/prod/outputs.tf` — contains `tenant_rds_endpoint`, `rds_proxy_endpoint`, `control_plane_rds_endpoint`
- [x] Commit `4b3282d` exists

## Self-Check: PASSED

---
*Phase: 03-databases-and-secrets*
*Completed: 2026-06-24*
