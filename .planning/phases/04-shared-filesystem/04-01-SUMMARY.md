---
phase: 04-shared-filesystem
plan: "01"
subsystem: efs
tags: [efs, filesystem, security-group, networking, mount-target]
dependency_graph:
  requires: [01-networking-module]
  provides: [modules/efs implemented, private_subnets_by_az networking output]
  affects: [04-02-PLAN.md (root wiring consumes these)]
tech_stack:
  added: []
  patterns: [for_each over map(string), SG-reference NFS ingress, AWS-managed EFS encryption, IA lifecycle tiering]
key_files:
  created: []
  modified:
    - modules/efs/main.tf
    - modules/efs/variables.tf
    - modules/efs/outputs.tf
    - modules/networking/outputs.tf
decisions:
  - "Added private_subnets_by_az to modules/networking/outputs.tf as map(string) using for expression over var.azs — enables offline AZ-keyed for_each in mount targets (D-04)"
  - "EFS SG uses security_groups = [var.task_security_group_id] (SG-reference, not CIDR) — mirrors Phase 1/3 pattern, satisfies T-04-02"
  - "encrypted=true with no kms_key_id — uses AWS-managed aws/elasticfilesystem key (D-03 / T-04-01), defers CMK to hardening pass"
  - "Two lifecycle_policy blocks: transition_to_ia=AFTER_30_DAYS and transition_to_primary_storage_class=AFTER_1_ACCESS — IA cost savings without hot-file latency penalty (D-01)"
  - "No aws_efs_access_point or aws_efs_backup_policy — per-tenant access points are adapter-owned at runtime; backups deferred (D-02)"
metrics:
  duration: "~4 minutes"
  completed: "2026-06-24"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 4
---

# Phase 4 Plan 1: EFS Module Implementation Summary

Encrypted EFS filesystem with SG-reference NFS ingress, per-AZ mount targets via for_each, and efs_id output — plus private_subnets_by_az networking output for offline AZ-keyed wiring.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extend modules/networking/outputs.tf with private_subnets_by_az | 5c8108f | modules/networking/outputs.tf |
| 2 | Implement modules/efs (variables, main, outputs) | b4d5ab2 | modules/efs/main.tf, modules/efs/variables.tf, modules/efs/outputs.tf |

## What Was Built

### Task 1: private_subnets_by_az networking output

Extended `modules/networking/outputs.tf` with a fifth output:

```hcl
output "private_subnets_by_az" {
  description = "Map of AZ to public subnet id for EFS mount target per-AZ placement."
  value       = { for i, az in var.azs : az => aws_subnet.public[i].id }
}
```

Uses the established count-indexed invariant (`aws_subnet.public[i]` corresponds to `var.azs[i]`). Fully static — no data sources, satisfying D-06 offline plan requirement.

### Task 2: modules/efs fully implemented

Three resource blocks in `modules/efs/main.tf`:

1. `aws_security_group.efs` — NFS port 2049 ingress from task SG only (SG-reference, not CIDR). Mirrors the Phase 1/3 pattern exactly.
2. `aws_efs_file_system.main` — encrypted=true (AWS-managed key), generalPurpose, elastic, two lifecycle_policy blocks for IA tiering.
3. `aws_efs_mount_target.main` — for_each over `var.subnet_ids_by_az` map, one mount target per AZ with no duplicate-AZ risk.

`modules/efs/variables.tf` declares 4 variables: `name_prefix`, `vpc_id`, `task_security_group_id`, `subnet_ids_by_az`.

`modules/efs/outputs.tf` exports `efs_id` with provisioner arrow-notation description.

## Deviations from Plan

None - plan executed exactly as written.

## Threat Surface Scan

Both threat mitigations from the plan's threat register are implemented:

- T-04-01 (Information Disclosure — at-rest encryption): `encrypted = true` on `aws_efs_file_system.main`; no `kms_key_id` uses AWS-managed `aws/elasticfilesystem` key.
- T-04-02 (Elevation of Privilege — SG ingress): `security_groups = [var.task_security_group_id]` in the EFS SG ingress block; no `cidr_blocks` anywhere in the ingress block.

No new security-relevant surface beyond what the plan anticipated.

## Known Stubs

None — all implemented resources are complete. This plan intentionally excludes `aws_efs_access_point` (adapter-owned at runtime) and `aws_efs_backup_policy` (deferred MVP decision D-02).

## Self-Check

### Created/Modified Files Exist

- `modules/efs/main.tf` — 3 resource blocks, 0 access points
- `modules/efs/variables.tf` — 4 variables
- `modules/efs/outputs.tf` — efs_id output
- `modules/networking/outputs.tf` — 5 outputs including private_subnets_by_az

### Commits Exist

- 5c8108f: feat(04-01): add private_subnets_by_az output to modules/networking
- b4d5ab2: feat(04-01): implement modules/efs — encrypted filesystem, SG, per-AZ mount targets

## Self-Check: PASSED
