# platform-terraform

## What This Is

Terraform for the **shared AWS baseline** of the Odoo Entitlements SaaS platform. It provisions the long-lived, fleet-wide resources (networking, container platform, databases, routing/TLS, secrets) that the `provisioner` worker's `AwsDeploymentAdapter` assumes already exist before it creates *per-tenant* resources. The target architecture is locked in `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md`: **ECS/Fargate + one shared RDS PostgreSQL (database-per-tenant)**, chosen for cost-effectiveness and low maintenance.

## Core Value

`terraform` in `envs/prod` produces a correct, well-formed plan for the shared AWS baseline — every module the provisioner depends on is implemented, wired, and exports the identifiers the `AwsDeploymentAdapter` needs.

## Current Milestone: v1.1 Complete the shared AWS baseline

**Goal:** Implement, wire, and contract-export the 10 remaining `modules/*` so `terraform plan` in `envs/prod` produces a correct, well-formed plan for the *entire* baseline the provisioner's `AwsDeploymentAdapter` depends on.

**Target modules (locked SEED-001 build order):**
- `ecr` — pull-through cache from GHCR for the `odoo-core` image
- `ecs` — shared Fargate cluster
- `rds-tenant` (Single-AZ) + `rds-proxy` — shared tenant DB + proxy (activated ~30 tenants)
- `rds-control-plane` (Multi-AZ) — separate provisioner control-plane DB (blast-radius isolation; 99.9% SLA)
- `efs` — shared filesystem, per-tenant access points created by the adapter (durable across Fargate cross-AZ reschedule — not EBS)
- `acm` — wildcard cert for `*.{tenant_domain}`
- `alb` — host-based routing, idle timeout >60s (Odoo longpoll)
- `route53` — hosted zone for `tenant_domain`
- `ssm` — Parameter Store SecureStrings (HMAC salt, RDS master creds)

**Per-module done = same as networking:** implement → uncomment its call in `envs/prod/main.tf` → wire its `envs/prod/outputs.tf` contract outputs → pass the offline `make plan-check` gate. Verification stays **code-complete only** (no `terraform apply`).

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Repo scaffold: `bootstrap/` + `envs/prod/` + 10 stub `modules/` — existing
- ✓ S3 remote-state backend with native S3 locking (`use_lockfile=true`, no DynamoDB), provisioned by `bootstrap/` — existing
- ✓ `name_prefix` naming/tagging contract threaded to every module; all wiring lives in `envs/prod/main.tf` (no module-to-module calls) — existing
- ✓ Typed Terraform→provisioner output contract in `envs/prod/outputs.tf` — networking outputs now active (`vpc_id`, `private_subnet_ids`, `task_security_group_id`, `alb_security_group_id`); the rest remain commented pending their modules

<!-- Validated in Phase 1: Networking module -->

- ✓ **NET-01**: `modules/networking` implements a VPC for the prod baseline — Phase 1
- ✓ **NET-02**: Public subnets across ≥2 AZs, **no NAT gateway** (cost decision) — Phase 1
- ✓ **NET-03**: ALB security group (ingress 80/443 from internet) — Phase 1
- ✓ **NET-04**: Task security group that accepts port 8069 **only** from the ALB SG (SG-reference source, not CIDR) — Phase 1
- ✓ **NET-05**: Module exports the four contract outputs and the `envs/prod` networking call + outputs are uncommented — Phase 1
- ✓ **NET-06**: `terraform fmt` + `terraform validate` pass and a non-empty `terraform plan` (9 resources) is produced via the offline `make plan-check` gate — Phase 1

<!-- Validated in Phase 2: Container platform -->

- ✓ **ECR-01/ECR-02**: `modules/ecr` implements a **managed** `aws_ecr_repository` for `odoo-core` (immutable tags, scan-on-push, AES256, untagged-image lifecycle) — managed repo, **not** the rejected GHCR pull-through cache (CONTEXT D-01); exports `image_uri` from `repository_url` — Phase 2
- ✓ **ECS-01/ECS-02**: `modules/ecs` implements a shared ECS/Fargate cluster (Container Insights, FARGATE + FARGATE_SPOT capacity providers); exports `cluster_arn` — Phase 2
- ✓ **VER-01**: ecr/ecs wired into `envs/prod`; `make plan-check` green with 13 resources in the plan and `ecr_image_uri` + `ecs_cluster_arn` contract outputs active — Phase 2

<!-- Validated in Phase 3: Databases and secrets -->

- ✓ **SSM-01/SSM-02**: `modules/ssm` generates RDS master passwords + HMAC salt via `random_password` and stores them as `aws_ssm_parameter` SecureStrings (`ignore_changes = [value]`); exports only names/ARNs + sensitive pass-throughs — no secret values in plaintext outputs/state — Phase 3
- ✓ **RDS-01**: `modules/rds-tenant` implements a Single-AZ PostgreSQL instance with the RDS SG accepting 5432 **only** from the task SG (SG-reference, not CIDR), master creds from SSM — Phase 3
- ✓ **RDS-02**: `modules/rds-proxy` implements the full proxy resource set, all count-gated behind `enable_rds_proxy` (default false) with a `try()`-guarded endpoint — wired for activation at ~30 tenants — Phase 3
- ✓ **RDS-03**: `modules/rds-control-plane` implements a separate Multi-AZ PostgreSQL instance (`db_name = "provisioner"`), fully isolated from tenant RDS — Phase 3
- ✓ **RDS-04**: all four modules wired into `envs/prod` (underscore labels, `hashicorp/random` provider); `make plan-check` green with 27 resources and the three RDS/SSM contract outputs active — Phase 3

<!-- Validated in Phase 4: Shared filesystem -->

- ✓ **EFS-01**: `modules/efs` implements an encrypted EFS filesystem (`generalPurpose`/`elastic`, at-rest encryption, IA lifecycle tiering) with an EFS SG accepting NFS 2049 **only** from the task SG (SG-reference, not CIDR) and per-AZ mount targets via `for_each`; no per-tenant access points created by Terraform — Phase 4
- ✓ **EFS-02**: `module "efs"` wired into `envs/prod` (subnets from new `module.networking.private_subnets_by_az` output), `efs_id` contract output active; `make plan-check` green with 31 resources — Phase 4

### Active

<!-- Milestone v1.1: complete the shared baseline — the remaining modules. Full REQ-IDs in REQUIREMENTS.md; phases in ROADMAP.md. -->

- `efs` — shared filesystem with per-tenant access points
- `acm`, `alb`, `route53` — wildcard TLS, host-based routing, hosted zone

### Out of Scope

<!-- Explicit boundaries. -->

- `terraform apply` to real AWS — verification for this milestone remains code-complete only (fmt/validate + clean plan); no live apply, no cloud cost
- `envs/staging` and multi-region/DR — not needed until the baseline exists
- CI/CD pipeline, tfsec/checkov, Terratest — valuable (see CONCERNS.md) but not part of the networking milestone
- NAT gateway — deliberately excluded for cost; revisit at ~20+ tenants

## Context

- **Brownfield**, mapped 2026-06-19 → `.planning/codebase/` (STACK, ARCHITECTURE, STRUCTURE, CONVENTIONS, TESTING, INTEGRATIONS, CONCERNS).
- All 10 resource modules are currently empty stubs (header comment + `# TODO`); all `envs/prod/main.tf` module calls and `envs/prod/outputs.tf` outputs are commented out, so `terraform plan` succeeds vacuously today.
- Build order (SEED-001): `networking → ecr → ecs → rds-tenant/proxy/control-plane → efs/acm/alb/route53/ssm`. Networking is the foundation every other module consumes.
- Key networking concern from CONCERNS.md: tasks run on public subnets (no NAT), so the task SG must rigorously allow only 8069 from the ALB SG — any misconfiguration exposes tasks directly to the internet.
- Companion repos: `platform-infra` (local-dev Docker Compose) and `provisioner` (consumes these outputs as `DEPLOYMENT_ADAPTER=aws` settings).

## Constraints

- **Tech stack**: Terraform ≥ 1.11 (required for native S3 state locking), AWS provider `~> 6.0`. No DynamoDB lock table.
- **Architecture**: All module wiring done in `envs/prod/main.tf`; modules never call other modules. Every resource name prefixed with `var.name_prefix`. Secrets only ever via `modules/ssm` SecureStrings, never in plaintext outputs/state.
- **Cost**: No NAT gateway; Single-AZ tenant RDS at MVP; SSM Parameter Store over Secrets Manager. Cost-stripping is a locked SEED-001 theme.
- **Verification**: Code-complete only this milestone — `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan`. No `terraform apply`.
- **Region**: `eu-central-1` default (hardcoded in `envs/prod/backend.tf`, defaulted in tfvars).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| One milestone at a time (networking first) | User wants lean cadence: add one, implement, then next — avoid a big upfront roadmap | — Pending |
| Code-complete verification (no apply) | No AWS spend/creds required; fmt/validate + non-empty plan is sufficient confidence at this stage | — Pending |
| Public subnets, no NAT gateway | Cost; locked in SEED-001 | — Pending |
| Task SG accepts 8069 only from ALB SG | Tasks are internet-reachable on public subnets; tight SG is the only thing preventing direct exposure | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-24 — Phase 4 (shared filesystem) complete: modules/efs (encrypted, per-AZ mount targets, task-SG-scoped NFS) wired into envs/prod, plan-check green (31 resources)*
