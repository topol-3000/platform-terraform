# Phase 4: Shared filesystem - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-24
**Phase:** 4-shared-filesystem
**Areas discussed:** IA lifecycle tiering, Automatic backups, Encryption key, Mount-target AZ safety

---

## IA lifecycle tiering

| Option | Description | Selected |
|--------|-------------|----------|
| IA after 30d + return on access | transition_to_ia = AFTER_30_DAYS, transition_to_primary_storage_class = AFTER_1_ACCESS. Cold files cheapen; reads pull them back to Standard so hot session/asset files dodge IA latency. | ✓ |
| No tiering (all Standard) | Omit lifecycle_policy. Lowest latency, simplest, minor savings forgone. | |
| IA after 7d, no return | Aggressive cost; cold reads keep paying IA latency (risks /sessions warning). | |

**User's choice:** IA after 30d + return on access (Recommended)
**Notes:** The return-on-access transition is the explicit mitigation for the SEED-001 small-file latency warning under /sessions — cost savings without punishing hot reads.

---

## Automatic backups

| Option | Description | Selected |
|--------|-------------|----------|
| Off for MVP, deferred | No aws_efs_backup_policy this phase; matches cost-lean pattern; noted as near-term hardening item. | ✓ |
| Enable backups now | aws_efs_backup_policy ENABLED — protect durable filestore from day one; adds cost + resource. | |
| Feature-flagged (default off) | Backup policy gated behind var.enable_efs_backup, mirroring enable_rds_proxy. | |

**User's choice:** Off for MVP, deferred (Recommended)
**Notes:** Chosen over the feature-flag variant to keep the module lean. EFS holds durable filestore/attachments, so backups are explicitly deferred (not rejected) — expected to return in a hardening pass.

---

## Encryption key (CMK vs managed)

| Option | Description | Selected |
|--------|-------------|----------|
| AWS-managed key | encrypted = true with default aws/elasticfilesystem key. Cheapest, offline, consistent with RDS/SSM (Phase 3 D-09). | ✓ |
| Customer-managed CMK now | aws_kms_key for EFS (audit + rotation); pulls deferred CMK work forward for one module. | |

**User's choice:** AWS-managed key (Recommended)
**Notes:** Carry-forward of Phase 3 D-09; CMK stays deferred to the security-hardening pass.

---

## Mount-target AZ safety

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit per-AZ dedup guard | Mount targets keyed by AZ so two subnets in one AZ can't cause a duplicate-MT apply failure the offline plan won't catch. | ✓ |
| Trust Phase 1 layout (per-subnet) | for_each over private_subnet_ids directly; safe today (one subnet per AZ) but fragile to layout changes. | |

**User's choice:** Explicit per-AZ dedup guard (Recommended)
**Notes:** Cheap robustness insurance with zero cost. Mechanism (AZ↔subnet mapping resolved offline, no data source) left to planner discretion in CONTEXT.md.

---

## Claude's Discretion

- AZ↔subnet mapping mechanism for the per-AZ mount-target guard (networking output vs direct for_each with invariant comment).
- aws_efs_mount_target style, resource/label naming, SG resource structure, creation_token.
- Whether to also export efs_arn/efs_dns_name (only efs_id is contractually required).

## Deferred Ideas

- EFS automatic backups (aws_efs_backup_policy) — near-term hardening item.
- Customer-managed KMS CMK for EFS at-rest encryption — deferred with the broader CMK work.
- Provisioned-throughput / non-elastic tuning — out of scope (elastic locked).
- Per-tenant EFS access points — adapter-owned at runtime, never Terraform.
