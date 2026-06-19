# platform-terraform

## What This Is

Terraform for the **shared AWS baseline** of the Odoo Entitlements SaaS platform. It provisions the long-lived, fleet-wide resources (networking, container platform, databases, routing/TLS, secrets) that the `provisioner` worker's `AwsDeploymentAdapter` assumes already exist before it creates *per-tenant* resources. The target architecture is locked in `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md`: **ECS/Fargate + one shared RDS PostgreSQL (database-per-tenant)**, chosen for cost-effectiveness and low maintenance.

## Core Value

`terraform` in `envs/prod` produces a correct, well-formed plan for the shared AWS baseline — every module the provisioner depends on is implemented, wired, and exports the identifiers the `AwsDeploymentAdapter` needs.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Repo scaffold: `bootstrap/` + `envs/prod/` + 10 stub `modules/` — existing
- ✓ S3 remote-state backend with native S3 locking (`use_lockfile=true`, no DynamoDB), provisioned by `bootstrap/` — existing
- ✓ `name_prefix` naming/tagging contract threaded to every module; all wiring lives in `envs/prod/main.tf` (no module-to-module calls) — existing
- ✓ Typed Terraform→provisioner output contract in `envs/prod/outputs.tf` — existing (currently commented pending module implementation)

### Active

<!-- Current milestone: networking module only. -->

- [ ] **NET-01**: `modules/networking` implements a VPC for the prod baseline
- [ ] **NET-02**: Public subnet(s) across AZs, **no NAT gateway** (cost decision)
- [ ] **NET-03**: ALB security group (ingress 80/443 from internet)
- [ ] **NET-04**: Task security group that accepts port 8069 **only** from the ALB SG
- [ ] **NET-05**: Module exports the outputs the contract needs (`vpc_id`, `private_subnet_ids`, `task_security_group_id`, `alb_security_group_id`) and the `envs/prod` networking call + outputs are uncommented
- [ ] **NET-06**: `terraform fmt` + `terraform validate` pass and `terraform plan` produces a clean, non-empty plan for the networking resources

### Out of Scope

<!-- Explicit boundaries. -->

- All other modules (ecr, ecs, rds-*, efs, alb, acm, route53, ssm) — deferred to future milestones; one milestone at a time per the user's cadence
- `terraform apply` to real AWS — verification for this milestone is code-complete only (fmt/validate + clean plan); no live apply, no cloud cost
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
*Last updated: 2026-06-19 after initialization*
