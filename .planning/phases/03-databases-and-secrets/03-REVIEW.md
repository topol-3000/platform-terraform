---
phase: 03-databases-and-secrets
reviewed: 2026-06-24T00:00:00Z
depth: standard
files_reviewed: 14
files_reviewed_list:
  - modules/ssm/main.tf
  - modules/ssm/outputs.tf
  - modules/rds-tenant/variables.tf
  - modules/rds-tenant/main.tf
  - modules/rds-tenant/outputs.tf
  - modules/rds-control-plane/variables.tf
  - modules/rds-control-plane/main.tf
  - modules/rds-control-plane/outputs.tf
  - modules/rds-proxy/variables.tf
  - modules/rds-proxy/main.tf
  - modules/rds-proxy/outputs.tf
  - envs/prod/versions.tf
  - envs/prod/variables.tf
  - envs/prod/main.tf
  - envs/prod/outputs.tf
findings:
  critical: 0
  warning: 3
  info: 4
  total: 7
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-06-24
**Depth:** standard
**Files Reviewed:** 14
**Status:** issues_found

## Summary

Phase 3 implements the SSM secrets module and three RDS modules (tenant, control-plane, proxy) and wires them into `envs/prod`. The locked decisions D-01 through D-12 were honored well: secrets are generated offline via `random_password`, SSM SecureStrings use `ignore_changes = [value]`, sensitive outputs are marked `sensitive = true` and are NOT re-exported in the provisioner contract, the 5432 ingress rules all use SG references (no CIDR), the proxy is fully count-gated behind `enable_rds_proxy` with a `try()`-guarded endpoint output, the tenant DB is Single-AZ and the control-plane DB is Multi-AZ, both DBs have deletion protection + final snapshot, and `hashicorp/random` was added to `required_providers`. The offline plan gate is preserved (no `data` sources, no STS/account-id lookups).

No Critical defects were found. The findings below are correctness/robustness concerns: a duplicated `final_snapshot_identifier` collision risk across rebuilds, a proxy-target ordering hazard, and a master-username inconsistency that will surface only when the proxy is activated. The region/AZ defaults contradicting the documented `eu-central-1` are pre-existing (not introduced this phase) and noted as Info.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: `final_snapshot_identifier` is static — a destroy/recreate cycle will collide with the retained snapshot

**File:** `modules/rds-tenant/main.tf:82`, `modules/rds-control-plane/main.tf:83`
**Issue:** Both instances hardcode a fixed final snapshot name:
```hcl
final_snapshot_identifier = "${var.name_prefix}-tenant-rds-final"
final_snapshot_identifier = "${var.name_prefix}-cp-rds-final"
```
When an instance is destroyed, AWS creates a final snapshot under this exact name. RDS final snapshot identifiers are unique per account/region and are NOT deleted with the instance. If the instance is later recreated and destroyed again (or destroyed after a prior destroy left the snapshot behind), the second destroy fails with `DBSnapshotAlreadyExists`, leaving the instance un-destroyable until the operator manually deletes the old snapshot. Because the value is also constant, two stacks/environments sharing a `name_prefix` collision would clash. This is a latent operational footgun even though `apply` is out of scope this milestone.
**Fix:** Make the identifier unique per destroy, e.g. append a timestamp or random suffix so each final snapshot is distinct:
```hcl
final_snapshot_identifier = "${var.name_prefix}-tenant-rds-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"
```
(or use a `random_id` keepers-rotated suffix). If the static name is intentional for recoverability, document that the operator must manually delete the prior `-final` snapshot before any recreate.

### WR-02: Proxy master username is hardcoded in `envs/prod/main.tf` instead of being derived from the tenant DB

**File:** `envs/prod/main.tf:65`, cross-ref `modules/rds-tenant/main.tf:69`
**Issue:** The tenant DB master username is hardcoded as `username = "odoo_master"` in the tenant module, and `envs/prod/main.tf` independently passes `master_username = "odoo_master"` to the proxy module. These are two separate literals that MUST stay equal for proxy auth to succeed (the proxy authenticates to the backend RDS using these credentials). If either literal is ever changed without the other, the proxy will fail authentication at runtime — and because the proxy is count-gated OFF, `terraform plan`/`validate` will not catch the drift. The rds-tenant module does not expose its `username` as an output, so there is no single source of truth.
**Fix:** Add a `username` output to `modules/rds-tenant/outputs.tf` and wire it through:
```hcl
# modules/rds-tenant/outputs.tf
output "master_username" {
  description = "RDS master username. Passed to rds-proxy for Secrets Manager auth."
  value       = aws_db_instance.tenant.username
}
```
```hcl
# envs/prod/main.tf, module "rds_proxy"
master_username = module.rds_tenant.master_username
```
This removes the duplicated literal and guarantees the proxy secret matches the backend credentials.

### WR-03: `aws_db_proxy_target` may race the proxy/target-group readiness without an explicit dependency, and targets the tenant DB by identifier only

**File:** `modules/rds-proxy/main.tf:124-129`
**Issue:** `aws_db_proxy_target.this` references `db_proxy_name` and `target_group_name` from the proxy and default target group (good — establishes implicit deps), but `db_instance_identifier = var.db_instance_identifier` is a plain string variable, not a reference to the tenant `aws_db_instance`. When the proxy is enabled, Terraform has no dependency edge guaranteeing the tenant RDS instance exists/is available before the proxy target is registered. Registering a proxy target against a not-yet-available DB instance can fail. Additionally, when `enable_rds_proxy = false`, `db_instance_identifier` defaults to `""`; the resource is count-gated to 0 so it never evaluates, which is correct — but the only thing keeping the empty string safe is the count gate, so any future un-gating must restore a real value first.
**Fix:** Because cross-module dependency edges flow through the root, ensure `envs/prod/main.tf` keeps passing `module.rds_tenant.identifier` (it does, line 61) so the DAG orders rds_tenant before rds_proxy. Optionally add `depends_on = [var…]` is not possible across the variable boundary — instead document that the proxy must only be enabled after the tenant instance is applied, or pass and consume the tenant instance via a dependency the module can `depends_on`. At minimum, add a comment at line 128 noting the ordering relies on the root-level `module.rds_tenant.identifier` reference.

## Info

### IN-01: Region and AZ defaults contradict the documented `eu-central-1` baseline (pre-existing)

**File:** `envs/prod/variables.tf:4` (`region` default `us-east-1`), `envs/prod/variables.tf:42` (`azs` default `["us-east-1a","us-east-1b"]`), `envs/prod/backend.tf:10`
**Issue:** CLAUDE.md states the region is `eu-central-1` (default, hardcoded in `backend.tf`, defaulted in tfvars). The actual defaults are `us-east-1`. The `azs` default directly feeds the RDS DB subnet groups created this phase, so a mismatch between `region` and `azs` (e.g. operator sets `region = eu-central-1` but leaves the `us-east-1a/b` AZ default) would produce an invalid plan/apply. These values were NOT modified in Phase 3 (the phase-3 commit only appended `enable_rds_proxy` and the four `rds_*` sizing vars), so this is an inherited discrepancy, not a phase-3 regression. Flagging because the RDS subnet groups now depend on `azs` being internally consistent with `region`.
**Fix:** Reconcile the documented region with the code. Either update CLAUDE.md to `us-east-1`, or change the `region`/`azs`/`backend.tf` defaults to `eu-central-1` / `["eu-central-1a","eu-central-1b"]`. Out of scope for this phase but should be tracked.

### IN-02: Per-phase sizing vars do not allow independent tenant vs control-plane tuning

**File:** `envs/prod/variables.tf:55-77`, `envs/prod/main.tf:50-53,77-80`
**Issue:** `rds_instance_class`, `rds_engine_version`, `rds_allocated_storage`, and `rds_max_allocated_storage` are single variables applied to BOTH the tenant and control-plane instances. The control-plane DB (Multi-AZ, provisioner SLA) and the tenant DB (Single-AZ, cost-stripped) have different sizing rationales per SEED-001, but they cannot be tuned independently without editing the module wiring. This is acceptable at MVP (both default to `db.t4g.small`), but couples two instances that the architecture deliberately isolates.
**Fix:** If independent sizing is anticipated, split into `tenant_rds_*` and `cp_rds_*` variable sets. Otherwise document that shared sizing is an intentional MVP simplification.

### IN-03: `override_special` set is duplicated verbatim across three `random_password` resources

**File:** `modules/ssm/main.tf:12,20,28`
**Issue:** The `override_special = "!#$%&*()-_=+[]{}<>:?"` literal is repeated for all three passwords. If the safe-character set ever needs adjusting (e.g. a character later found to break a connection string), it must be changed in three places. Minor maintainability concern.
**Fix:** Hoist to a `locals` block (`local.password_special`) and reference it in all three resources.

### IN-04: HMAC salt generated via `random_password` rather than `random_id`/`random_bytes`

**File:** `modules/ssm/main.tf:25-29`
**Issue:** The HMAC salt is generated with `random_password` (32 chars from a constrained special set). For a cryptographic salt, a raw-byte/base64 source (`random_bytes` or `random_id`) gives a cleaner, higher-entropy value without the printable-character constraints. `random_password` works and the value is sufficiently random, but the resource type signals "password," not "salt." Functionally correct; semantic nit. The CONTEXT (D-01) explicitly allows either `random_password`/`random_id`, so this is within spec.
**Fix:** Optional — consider `random_bytes` for the salt to make intent explicit and remove the unnecessary special-character constraint.

---

_Reviewed: 2026-06-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
