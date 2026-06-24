# Milestones

## v1.1 Complete the shared AWS baseline (Shipped: 2026-06-24)

**Scope:** Phases 2–5 (Phase 1 shipped earlier as v1.0 Networking, 2026-06-19).
**Delivered:** 4 phases, 13 plans — implemented, wired, and contract-exported the 10 remaining `modules/*`, completing the full shared AWS baseline the provisioner's `AwsDeploymentAdapter` depends on.

**Stats:**
- Commits: 82 (20 `feat`) · 87 files · +11,409 / −228
- Terraform LOC: 1,568 (`modules/` + `envs/` + `bootstrap/`)
- Timeline: 2026-06-23 → 2026-06-24 (2 days)
- Final `make plan-check`: green at **36 resources**, all provisioner contract outputs resolvable

**Key accomplishments:**

- **Container platform (Phase 2)** — managed `aws_ecr_repository` for `odoo-core` (immutable tags, scan-on-push, AES256, untagged-image lifecycle; `image_uri` from `repository_url`) + shared ECS/Fargate cluster (Container Insights, FARGATE + FARGATE_SPOT)
- **Databases & secrets (Phase 3)** — Single-AZ tenant RDS (5432 only from task SG) + count-gated RDS Proxy (`enable_rds_proxy`, default false) + isolated Multi-AZ control-plane RDS; master creds + HMAC salt generated via `random_password` and stored as SSM SecureStrings — no plaintext secrets in outputs/state
- **Shared filesystem (Phase 4)** — encrypted EFS (`generalPurpose`/`elastic`, IA tiering) with per-AZ mount targets and NFS 2049 scoped to the task SG; no per-tenant access points created by Terraform
- **TLS & routing (Phase 5)** — wildcard ACM cert for `*.{tenant_domain}` (DNS validation), shared ALB with HTTP→HTTPS 301 redirect + HTTPS TLS 1.3 (`idle_timeout=120` for Odoo longpoll), public Route53 hosted zone
- **Full provisioner output contract** satisfied — all 10 baseline modules wired in `envs/prod`, `make plan-check` green at 36 resources

**Known deferred items at close:** 2 (see STATE.md Deferred Items) — Phase 05 UAT (resolved, 0 pending) and quick task `260622-opq-switch-region-us-east-1` (missing completion manifest).

---
