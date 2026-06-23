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

### Active

<!-- Milestone v1.1: complete the shared baseline — the 10 remaining modules. Full REQ-IDs in REQUIREMENTS.md; phases in ROADMAP.md. -->

- `ecr`, `ecs` — container platform (pull-through cache + shared Fargate cluster)
- `rds-tenant` + `rds-proxy`, `rds-control-plane` — tenant DB + proxy, separate Multi-AZ control-plane DB
- `efs` — shared filesystem with per-tenant access points
- `acm`, `alb`, `route53` — wildcard TLS, host-based routing, hosted zone
- `ssm` — Parameter Store SecureStrings for secrets

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
*Last updated: 2026-06-23 — started milestone v1.1 (complete the shared AWS baseline)*
