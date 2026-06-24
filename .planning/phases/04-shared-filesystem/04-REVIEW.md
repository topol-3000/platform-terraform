---
phase: 04-shared-filesystem
reviewed: 2026-06-24T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - envs/prod/main.tf
  - envs/prod/outputs.tf
  - modules/efs/main.tf
  - modules/efs/outputs.tf
  - modules/efs/variables.tf
  - modules/networking/outputs.tf
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-06-24
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Phase 04 implements `modules/efs` (encrypted shared EFS filesystem, NFS security group, per-AZ mount targets, `efs_id` output) and wires it into `envs/prod/main.tf`, plus adds a `private_subnets_by_az` output to `modules/networking`. The offline gate is healthy: `terraform fmt -check -recursive` passes, `terraform validate` passes, and `make plan-check` produces a non-empty plan (31 resources to add, `efs_id` exported). Conventions from CLAUDE.md are respected — every resource is `var.name_prefix`-prefixed, all wiring is in the root (no module-to-module calls), the EFS SG uses an SG-reference ingress (not CIDR), and the `for_each`-over-AZ-map dedup is in place.

No Critical issues. The findings below are robustness/correctness concerns: an unenforced uniqueness invariant behind the `for_each` map that can silently drop a mount target, a data-durability gap (no backup policy on a filesystem framed as "durable"), and a coupling/silent-failure risk between the networking AZ→subnet zip and the EFS mount-target placement. None block a code-complete (`plan`-only) milestone, but they should be addressed before any `apply`.

## Warnings

### WR-01: `azs` list allows duplicate AZs, silently dropping an EFS mount target

**File:** `modules/networking/outputs.tf:21-24` (consumed by `modules/efs/main.tf:51-57`)
**Issue:** `private_subnets_by_az` is built as `{ for i, az in var.azs : az => aws_subnet.public[i].id }`. If `var.azs` ever contains a duplicate AZ string (e.g. `["eu-central-1a", "eu-central-1a"]`), the map comprehension silently collapses to a single key (last-write-wins), so one of the `aws_subnet.public` subnets gets **no** mount target. EFS mount targets are per-AZ, so a duplicate is genuinely invalid — but the only guard on `azs` is `length(var.azs) >= 2` (`modules/networking/variables.tf:20-23` and `envs/prod/variables.tf:43-46`), which a duplicate list passes. The result is a subnet whose ECS tasks cannot reach EFS, with no plan-time error. The map-based `for_each` was explicitly chosen for AZ dedup (D-04), but it dedups by *collapsing*, not by *rejecting*, so the failure is silent rather than loud.
**Fix:** Add a uniqueness `validation` block to the `azs` variable so a duplicate fails the plan loudly instead of silently dropping a subnet:
```hcl
variable "azs" {
  type = list(string)
  # ...
  validation {
    condition     = length(var.azs) == length(distinct(var.azs))
    error_message = "azs must not contain duplicate availability zones (one EFS mount target is created per AZ)."
  }
}
```
(Note: `modules/networking/variables.tf` is outside the Phase 04 change set, but the defect is exposed by the Phase 04 `private_subnets_by_az` output and EFS `for_each`; the validation belongs on the `azs` source variable.)

### WR-02: No backup policy on a filesystem documented as "durable" Odoo filestore

**File:** `modules/efs/main.tf:32-48`
**Issue:** The `aws_efs_file_system.main` header comment describes it as holding "durable Odoo filestore/session data across task replacement," and SEED-001 frames EFS as the durability layer (NOT EBS). Yet no `aws_efs_backup_policy` is declared, so AWS Backup is **disabled** for this filesystem. EFS data is replicated within a region but a backup policy is the only protection against accidental deletion / application-level corruption of tenant filestore data — a data-loss risk for the very data this module exists to protect. This is a deliberate MVP deferral per the plan (D-02), so it is not a blocker, but it should be tracked, not silently shipped: "durable" in the comment overstates the actual guarantee.
**Fix:** Either (a) add the backup policy now:
```hcl
resource "aws_efs_backup_policy" "main" {
  file_system_id = aws_efs_file_system.main.id
  backup_policy { status = "ENABLED" }
}
```
or (b) leave it deferred but soften the comment to avoid implying backup-grade durability, e.g. "durable across task replacement / cross-AZ reschedule; point-in-time backup deferred to a later phase (D-02) — no protection against accidental delete or corruption yet," and ensure a follow-up requirement exists before tenant data lands.

### WR-03: EFS mount-target placement silently depends on the `azs`-to-`public[i]` index invariant

**File:** `modules/networking/outputs.tf:23` (paired with `modules/networking/main.tf:17-26` and `modules/efs/main.tf:51-57`)
**Issue:** `private_subnets_by_az` zips `var.azs[i]` to `aws_subnet.public[i].id` purely by positional index, relying on the invariant that `aws_subnet.public` is `count`-indexed in the same order as `var.azs`. This invariant holds today (`availability_zone = var.azs[count.index]`), but it is implicit — nothing enforces that the subnet at index `i` actually lives in `var.azs[i]`. If the subnet resource is ever refactored to `for_each`, reordered, or filtered, the map would associate an AZ key with a subnet in a *different* AZ. EFS would then create a mount target whose declared subnet is in another AZ — `aws_efs_mount_target` derives its AZ from the subnet, so the map *key* becomes a lie, and any future consumer that trusts the key (or any per-AZ uniqueness reasoning) breaks silently. It plans cleanly because the key is never validated against the subnet's real AZ.
**Fix:** Derive the AZ from the subnet attribute rather than re-using the input list, so the key cannot drift from the subnet's true AZ:
```hcl
output "private_subnets_by_az" {
  description = "Map of AZ to public subnet id for EFS mount target per-AZ placement."
  value       = { for s in aws_subnet.public : s.availability_zone => s.id }
}
```
This keys off `aws_subnet.public[*].availability_zone` (the resource's own AZ), removing the positional-index assumption and making a duplicate AZ collapse on the authoritative attribute.

## Info

### IN-01: `subnet_ids_by_az` / `private_subnets_by_az` descriptions say "public subnet" while module names use "private"

**File:** `modules/efs/variables.tf:16-19`, `modules/networking/outputs.tf:6-9` and `:21-24`
**Issue:** The architecture uses public subnets only (no NAT). The descriptions correctly say "public subnet," but the identifiers (`private_subnet_ids`, `private_subnets_by_az`) and `output "private_subnet_ids"`'s own description ("IDs of the public subnets...") carry the legacy "private" name. This is a naming/comment mismatch that can mislead a reader into thinking tenant tasks sit in private subnets (they do not — `map_public_ip_on_launch = true`). Pre-existing for `private_subnet_ids`; `private_subnets_by_az` perpetuates it.
**Fix:** Low priority and cross-cutting (the provisioner contract may already key on `private_subnet_ids`). If renamed, do it consistently across `modules/networking/outputs.tf`, `envs/prod/outputs.tf`, and the EFS variable in a dedicated rename change — not piecemeal. Otherwise leave a one-line note that "private" is historical and these are public subnets.

### IN-02: EFS SG egress is allow-all `0.0.0.0/0`

**File:** `modules/efs/main.tf:22-27`
**Issue:** The EFS security group has an allow-all egress rule. An EFS mount target is a passive NFS endpoint — it does not initiate outbound connections — so egress on the EFS SG is functionally unused; allow-all is harmless here but broader than necessary. It mirrors the project-wide SG egress convention (networking, RDS), so this is a consistency-vs-least-privilege note, not a bug.
**Fix:** Optional. For least privilege the egress block could be omitted or narrowed, but matching the established convention is acceptable; flag only if the project later tightens egress policy fleet-wide.

---

_Reviewed: 2026-06-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
