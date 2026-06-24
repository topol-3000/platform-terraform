---
phase: 03
slug: databases-and-secrets
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-24
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

Security audit of declared threat mitigations against implemented Terraform.
ASVS Level: L1. Audit basis: register authored at plan time (all 5 plans carried a `<threat_model>` block); mitigations verified in code.

Audited: 2026-06-24
Result: SECURED — 19/19 threats resolved (17 mitigated + verified, 2 accepted risks documented below).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| `random_password` → `aws_ssm_parameter` | Generated secret crosses from Terraform state into AWS SSM SecureString (encrypted at rest by `alias/aws/ssm`). | RDS master passwords, HMAC salt (high sensitivity) |
| `ssm` outputs → `rds-tenant` / `rds-control-plane` modules | Sensitive raw password passes between modules in-memory at plan/apply; never written to a non-sensitive output. | Raw passwords (high sensitivity) |
| `var.master_password` → `aws_db_instance` | Sensitive password crosses into RDS `password` argument — stored encrypted in S3 state. | Raw passwords (high sensitivity) |
| `var.master_password` → `aws_secretsmanager_secret_version` | Sole sanctioned Secrets Manager use; only when `enable_rds_proxy = true`. | Raw password (high sensitivity) |
| `aws_security_group` RDS ingress (5432) | Must only be reachable from the task SG; any CIDR-based ingress would expose the DB via public subnets. | DB network access (control) |
| `envs/prod/outputs.tf` → provisioner adapter | Only non-sensitive SSM names/ARNs and endpoint strings cross; raw secret values must never appear. | Endpoint strings / ARNs (non-sensitive) |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation (Evidence file:line) | Status |
|-----------|----------|-----------|-------------|---------------------------------|--------|
| T-03-01 | Information Disclosure | `modules/ssm/outputs.tf` | mitigate | `sensitive = true` on tenant_rds_password & cp_rds_password (`modules/ssm/outputs.tf:9,15`); absent from `envs/prod/outputs.tf` | closed |
| T-03-02 | Information Disclosure | `aws_ssm_parameter` value in state | mitigate | `type = "SecureString"` (`modules/ssm/main.tf:36,51,66`); state encrypted AES256 SSE (`bootstrap/main.tf:25-34`) | closed |
| T-03-03 | Tampering | `lifecycle ignore_changes = [value]` drift | accept | Accepted risk AR-01; by-design (`modules/ssm/main.tf:41,56,71`) | closed |
| T-03-SC-01 | Tampering (supply chain) | `hashicorp/random` provider | mitigate | Official HashiCorp provider `~> 3.0` (`envs/prod/versions.tf:10-13`) | closed |
| T-03-04 | Information Disclosure | `modules/rds-tenant/main.tf` master_password in state | mitigate | `password = var.master_password` (`:70`); `ignore_changes = [password]` (`:89-91`) | closed |
| T-03-05 | Elevation of Privilege | `aws_security_group.rds_tenant` ingress 5432 | mitigate | `security_groups = [var.task_security_group_id]`, no `cidr_blocks` (`modules/rds-tenant/main.tf:14-20`) | closed |
| T-03-06 | Information Disclosure | rds-tenant `publicly_accessible` | mitigate | `publicly_accessible = false` (`modules/rds-tenant/main.tf:76`) | closed |
| T-03-07 | Tampering | rds-tenant deletion guards | mitigate | `deletion_protection = true`, `skip_final_snapshot = false` (`modules/rds-tenant/main.tf:80-81`) | closed |
| T-03-08 | Information Disclosure | `modules/rds-control-plane/main.tf` master_password | mitigate | `password = var.master_password` (`:72`); `ignore_changes = [password]` (`:90-92`) | closed |
| T-03-09 | Elevation of Privilege | `aws_security_group` cp_rds ingress | mitigate | `security_groups = [var.task_security_group_id]`, no `cidr_blocks` on 5432 (`modules/rds-control-plane/main.tf:13-19`) | closed |
| T-03-10 | Tampering | tenant/control-plane isolation | mitigate | `db_name = "provisioner"` (`:70`); distinct identifier/SG/subnet group (`:57,:9,:33`); no "tenant" labels | closed |
| T-03-11 | Tampering | control-plane deletion guards | mitigate | `deletion_protection = true`, `skip_final_snapshot = false` (`modules/rds-control-plane/main.tf:81-82`) | closed |
| T-03-12 | Information Disclosure | `aws_secretsmanager_secret_version` (proxy) | mitigate | `count` gated, default false (`modules/rds-proxy/main.tf:13-14,21-22`; `variables.tf:9`); encrypted at rest | closed |
| T-03-13 | Elevation of Privilege | `aws_iam_role_policy.proxy` GetSecretValue | mitigate | `Resource` scoped to `proxy_auth[0].arn`, not wildcard (`:58`); `rds.amazonaws.com` principal (`:40`) | closed |
| T-03-14 | Elevation of Privilege | `aws_security_group.proxy` ingress | mitigate | `security_groups = [var.task_security_group_id]`, no CIDR (`:76`); `count` gate, default false (`:67`) | closed |
| T-03-15 | Denial of Service | `aws_db_proxy` connection_pool_config | accept | Accepted risk AR-02; `max_connections_percent = 90`, `connection_borrow_timeout = 120` (`modules/rds-proxy/main.tf:118,120`) | closed |
| T-03-SC-02 | Tampering (supply chain) | provider registry | mitigate | Proxy adds no new providers; only `hashicorp/aws ~> 6.0` + approved `hashicorp/random` (`envs/prod/versions.tf`) | closed |
| T-03-16 | Information Disclosure | `envs/prod/outputs.tf` password leak | mitigate | No `module.ssm.*_password` references; only endpoint strings cross boundary (`envs/prod/outputs.tf:36-49`) | closed |
| T-03-17 | Tampering | module label hyphen vs underscore | mitigate | `module "rds_tenant"` (`:43`), `module "rds_control_plane"` (`:70`) — underscore labels (`envs/prod/main.tf`) | closed |
| T-03-18 | Spoofing | `hashicorp/random` missing from required_providers | mitigate | `random` block present in `required_providers` (`envs/prod/versions.tf:10-13`) | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01 | T-03-03 | SSM SecureString out-of-band rotation drift (see below) | gsd-security-auditor | 2026-06-24 |
| AR-02 | T-03-15 | RDS Proxy connection-pool exhaustion under load (see below) | gsd-security-auditor | 2026-06-24 |

### AR-01 (T-03-03) — SSM SecureString out-of-band rotation drift
- **Category:** Tampering
- **Component:** `aws_ssm_parameter` `lifecycle { ignore_changes = [value] }` (`modules/ssm/main.tf:41,56,71`)
- **Disposition:** ACCEPT (by design)
- **Rationale:** Password/HMAC-salt rotation is performed out-of-band (operationally, outside Terraform). `ignore_changes = [value]` deliberately prevents Terraform from reverting a rotated secret back to the original generated value, which would cause drift and a credential reset on every apply. The tradeoff is that Terraform no longer detects tampering with the parameter value via plan diff. Detection of unauthorized SSM parameter changes is delegated to AWS CloudTrail / Config (out of scope for this phase). Accepted for MVP.

### AR-02 (T-03-15) — RDS Proxy connection-pool exhaustion under load
- **Category:** Denial of Service
- **Component:** `aws_db_proxy_default_target_group.connection_pool_config` (`modules/rds-proxy/main.tf:117-121`)
- **Disposition:** ACCEPT (MVP)
- **Rationale:** `max_connections_percent = 90` reserves only 10% headroom; under extreme tenant concurrency the pool can saturate. `connection_borrow_timeout = 120` bounds the wait so callers fail fast rather than block indefinitely. The RDS Proxy itself is gated off by default (`enable_rds_proxy = false`) and only activated at ~30 active tenants, at which point pool sizing is to be re-tuned against observed load. Accepted for MVP.

*Accepted risks do not resurface in future audit runs.*

---

## Unregistered Flags

None. Both SUMMARY `## Threat Flags` sections (03-01, 03-02) explicitly state no new attack surface beyond the plan's threat model; all flags map to registered threat IDs (T-03-01, T-03-02, T-03-04..T-03-07).

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-24 | 19 | 19 | 0 | gsd-security-auditor (State B, register_authored_at_plan_time: true) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-24
