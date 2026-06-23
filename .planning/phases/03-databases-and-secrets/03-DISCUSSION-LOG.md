# Phase 3: Databases and secrets - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-23
**Phase:** 3-databases-and-secrets
**Areas discussed:** Secret values & RDS password flow, RDS Proxy (flagged-off vs. live), RDS defaults & safety, Encryption keys (KMS)

---

## Secret values & RDS password flow

| Option | Description | Selected |
|--------|-------------|----------|
| Terraform random_password | random_password generates the master pw at plan time → written to SSM SecureString + fed to aws_db_instance.password; ignore_changes for rotation. Fully offline, never hardcoded, value only in encrypted state + SSM. | ✓ |
| tfvars placeholder values | Operator supplies secrets via terraform.tfvars; SSM + RDS read var.*. Breaks zero-edit plan; real password on disk. | |
| Dummy value + ignore_changes | Dummy SSM value, real secret injected out-of-band post-apply. More moving parts; RDS still needs a real password. | |

**User's choice:** Terraform random_password
**Notes:** Central tension was RDS-01 ("sourced from SSM, not hardcoded") vs. the offline-plan gate (a data-source SSM read would break it). random_password resolves both — TF is the source of truth, value lives only in encrypted state + SSM SecureString.

---

## RDS Proxy: flagged-off vs. live

| Option | Description | Selected |
|--------|-------------|----------|
| Feature-flag, default OFF | Full proxy impl gated behind var.enable_rds_proxy=false via count; 0 resources now, SSM-only intact until activation. | ✓ |
| Fully provision now | Proxy + Secrets Manager secret + IAM role unconditionally; appears in plan but breaks SSM-only at MVP. | |
| Flag ON by default | Same flagged impl but default true; in plan now but pulls Secrets Manager into MVP by default. | |

**User's choice:** Feature-flag, default OFF
**Notes:** RDS Proxy auth mandates a Secrets Manager secret (cannot use SSM). Flag-gating off keeps the SSM-only constraint intact until the proxy is actually needed (~30 tenants). Consequence recorded as D-06: ROADMAP success criteria #3/#6 are reinterpreted as "declared & wired behind enable_rds_proxy" rather than "present in the plan."

---

## RDS defaults & safety

| Option | Description | Selected |
|--------|-------------|----------|
| Burstable small (t4g) | db.t4g.small both instances, gp3 ~20GB + autoscaling; sized on max_connections per SEED-001. | ✓ (sizing) |
| Micro everywhere | db.t4g.micro both; cheapest but tight for real connection counts. | |
| General-purpose (m-class) | m7g.large non-burstable; steadier but pricier, against cost theme. | |
| Protected, snapshot on delete | deletion_protection=true + skip_final_snapshot=false on BOTH. | ✓ (safety) |
| Tenant protected, CP strict | Same + prevent_destroy lifecycle on control-plane. | |
| Unprotected (easy teardown) | deletion_protection=false, skip_final_snapshot=true. Dangerous. | |

**User's choice:** Burstable small (t4g) for sizing; Protected, snapshot on delete for safety
**Notes:** Cost-lean defaults, overridable via tfvars; data safety non-negotiable on both instances. Extra control-plane prevent_destroy considered but not adopted (deferred).

---

## Encryption keys (KMS)

| Option | Description | Selected |
|--------|-------------|----------|
| AWS-managed keys now | alias/aws/ssm for SecureStrings; default RDS key for storage_encrypted. Zero extra resources, cheapest, offline. CMK deferred. | ✓ |
| Customer-managed CMK now | Dedicated CMK for SSM + RDS; audit/rotation but extra cost + bootstrap-ordering dependency. | |
| CMK for SSM only | CMK for SecureStrings, default key for RDS storage. Middle ground. | |

**User's choice:** AWS-managed keys now
**Notes:** Encryption is ON everywhere; customer-managed CMK (CONCERNS.md security rec) deferred to a later hardening pass to keep the MVP simple and cheap.

---

## Claude's Discretion

- Postgres major version (default a current stable major, e.g. 16; set engine_version + param-group family explicitly).
- Control-plane RDS SG ingress source (default 5432 from task SG, mirroring tenant pattern; refine if a dedicated provisioner SG is preferred).
- SSM parameter naming/paths under `${name_prefix}`.
- Concrete set of "tokens" SecureStrings (scaffold HMAC salt + both RDS master-credential params; placeholder for tokens only if a consumer is known).
- count/for_each vs single-resource style, resource ordering, parameter-group/subnet-group structure.

## Deferred Ideas

- Customer-managed KMS CMK for SSM SecureStrings + RDS storage (security-hardening pass).
- RDS Proxy activation (enable_rds_proxy=true) at ~30 tenants; validate Odoo bus LISTEN/NOTIFY through the proxy (connection pinning).
- Control-plane prevent_destroy / max protection (considered, not adopted).
- db.t4g.micro downsizing / m-class upsizing — available as tfvars overrides.
- Read replicas, external pooling beyond RDS Proxy, cross-region DR — out of MVP scope.
