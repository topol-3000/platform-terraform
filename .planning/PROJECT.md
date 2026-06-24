# platform-terraform

## What This Is

Terraform for the **shared AWS baseline** of the Odoo Entitlements SaaS platform. It provisions the long-lived, fleet-wide resources (networking, container platform, databases, routing/TLS, secrets) that the `provisioner` worker's `AwsDeploymentAdapter` assumes already exist before it creates *per-tenant* resources. The target architecture is locked in `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md`: **ECS/Fargate + one shared RDS PostgreSQL (database-per-tenant)**, chosen for cost-effectiveness and low maintenance.

## Core Value

`terraform` in `envs/prod` produces a correct, well-formed plan for the shared AWS baseline — every module the provisioner depends on is implemented, wired, and exports the identifiers the `AwsDeploymentAdapter` needs.

## Current State

**Shipped: v1.1 "Complete the shared AWS baseline" (2026-06-24).** The full shared AWS baseline is implemented and wired — all 10 `modules/*` (ecr, ecs, rds-tenant, rds-proxy, rds-control-plane, efs, acm, alb, route53, ssm) plus networking (v1.0) are uncommented in `envs/prod/main.tf` and export their `AwsDeploymentAdapter` contract outputs in `envs/prod/outputs.tf`. `make plan-check` is green at **36 resources** (fmt + validate + non-empty offline plan); the entire provisioner output contract is resolvable. Verification remained **code-complete only** — no `terraform apply`, no cloud spend.

Delivered (locked SEED-001 build order):
- `ecr` — **managed** `aws_ecr_repository` for `odoo-core` (immutable tags, scan-on-push, AES256, untagged-image lifecycle); `image_uri` from `repository_url`. *(Changed from the originally-planned GHCR pull-through cache — see Key Decisions / Phase 2 CONTEXT D-01.)*
- `ecs` — shared Fargate cluster (Container Insights, FARGATE + FARGATE_SPOT)
- `rds-tenant` (Single-AZ) + `rds-proxy` (count-gated behind `enable_rds_proxy`, default false; activates ~30 tenants)
- `rds-control-plane` (Multi-AZ) — separate provisioner control-plane DB (blast-radius isolation; 99.9% SLA)
- `efs` — shared encrypted filesystem, per-AZ mount targets; per-tenant access points created by the adapter at runtime
- `acm` — wildcard cert for `*.{tenant_domain}` (DNS validation)
- `alb` — HTTP→HTTPS 301 redirect + HTTPS TLS 1.3 listener, `idle_timeout=120` (Odoo longpoll)
- `route53` — public hosted zone for `tenant_domain`
- `ssm` — Parameter Store SecureStrings (HMAC salt, RDS master creds)

## Next Milestone Goals

Candidates for the next milestone (not yet committed — define via `/gsd-new-milestone`):
- **Live `terraform apply`** to a real AWS account — promote verification from plan-only to an applied, smoke-tested baseline.
- **CI/CD + policy scanning** — `tfsec`/`checkov`, Terratest, automated `plan-check` in CI (currently manual; see CONCERNS.md).
- **`envs/staging`** — now that the baseline exists, a second environment becomes worthwhile.

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

<!-- Validated in Phase 5: TLS and routing -->

- ✓ **ACM-01**: `modules/acm` implements a wildcard `aws_acm_certificate` for `*.{tenant_domain}` (DNS validation, `create_before_destroy`); no `aws_acm_certificate_validation` resource (D-02, plan-only milestone); exports `cert_arn` — Phase 5
- ✓ **ALB-01**: `modules/alb` implements the shared internet-facing ALB (`idle_timeout = 120` for Odoo longpoll) with an HTTP→HTTPS 301 listener and an HTTPS listener (`ELBSecurityPolicy-TLS13-1-2-2021-06`, fixed-response 503 default); exports `listener_arn` — Phase 5
- ✓ **DNS-01**: `modules/route53` declares the public `aws_route53_zone` for `tenant_domain` (`force_destroy = false`, no records, no VPC association per D-03); exports `hosted_zone_id` — Phase 5
- ✓ **TLS-02**: acm/alb/route53 wired into `envs/prod` (acm before alb so `cert_arn` resolves); `acm_cert_arn`, `alb_listener_arn`, `hosted_zone_id` contract outputs active; `make plan-check` green with 36 resources — completes the full provisioner output contract — Phase 5

### Active

<!-- Milestone v1.1 complete — all baseline modules implemented and wired. No active requirements. -->

_(none — milestone v1.1 complete)_

### Out of Scope

<!-- Explicit boundaries. -->

- `terraform apply` to real AWS — verification for this milestone remains code-complete only (fmt/validate + clean plan); no live apply, no cloud cost
- `envs/staging` and multi-region/DR — not needed until the baseline exists
- CI/CD pipeline, tfsec/checkov, Terratest — valuable (see CONCERNS.md) but not part of the networking milestone
- NAT gateway — deliberately excluded for cost; revisit at ~20+ tenants

## Context

- **Brownfield**, mapped 2026-06-19 → `.planning/codebase/` (STACK, ARCHITECTURE, STRUCTURE, CONVENTIONS, TESTING, INTEGRATIONS, CONCERNS).
- **All 11 modules are now implemented and wired** (networking + the 10 v1.1 modules); every `envs/prod/main.tf` call and `envs/prod/outputs.tf` output is uncommented and resolves. `make plan-check` is green at **36 resources** (offline, dummy-AWS plan). ~1,568 LOC of HCL across `modules/` + `envs/` + `bootstrap/`.
- Build order followed (SEED-001): `networking → ecr → ecs → rds-tenant/proxy/control-plane + ssm → efs → acm/alb/route53`.
- Key security invariant held throughout: tasks run on public subnets (no NAT), so every service SG (task 8069 ← ALB SG, RDS 5432 ← task SG, EFS 2049 ← task SG) uses SG-reference sources, never CIDRs.
- Default region is **`us-east-1`** (switched from eu-central-1 via quick task `260622-opq`, 2026-06-22); set in `envs/prod/backend.tf` + tfvars example.
- Companion repos: `platform-infra` (local-dev Docker Compose) and `provisioner` (consumes these outputs as `DEPLOYMENT_ADAPTER=aws` settings).

## Constraints

- **Tech stack**: Terraform ≥ 1.11 (required for native S3 state locking), AWS provider `~> 6.0`. No DynamoDB lock table.
- **Architecture**: All module wiring done in `envs/prod/main.tf`; modules never call other modules. Every resource name prefixed with `var.name_prefix`. Secrets only ever via `modules/ssm` SecureStrings, never in plaintext outputs/state.
- **Cost**: No NAT gateway; Single-AZ tenant RDS at MVP; SSM Parameter Store over Secrets Manager. Cost-stripping is a locked SEED-001 theme.
- **Verification**: Code-complete only through v1.1 — `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan`. No `terraform apply` (live apply is a next-milestone candidate).
- **Region**: `us-east-1` default (set in `envs/prod/backend.tf`, defaulted in tfvars; switched from eu-central-1 via quick task `260622-opq`).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| One milestone at a time (networking first) | User wants lean cadence: add one, implement, then next — avoid a big upfront roadmap | ✓ Good — v1.0 (networking) then v1.1 (remaining 10 modules) shipped cleanly |
| Code-complete verification (no apply) | No AWS spend/creds required; fmt/validate + non-empty plan is sufficient confidence at this stage | ✓ Good — offline `make plan-check` caught wiring/contract errors at zero cost; live apply deferred to next milestone |
| Public subnets, no NAT gateway | Cost; locked in SEED-001 | ✓ Good — held across all modules; SG-reference scoping is the sole exposure guard |
| Task SG accepts 8069 only from ALB SG | Tasks are internet-reachable on public subnets; tight SG is the only thing preventing direct exposure | ✓ Good — pattern extended to RDS (5432←task SG) and EFS (2049←task SG) |
| ECR managed repo, not GHCR pull-through cache (Phase 2 D-01) | AWS-native image storage; `repository_url` is a resource attribute, keeping `make plan-check` free of account-id/STS data sources | ✓ Good — offline plan stays clean |
| Module labels use underscores, not hyphens | Dir names hyphenated (`rds-control-plane`) but `module "rds_control_plane"` referenced as `module.rds_control_plane.*` (CONCERNS.md fragile area) | ✓ Good — wiring resolved without label errors |
| SSM SecureStrings with `random_password` + `ignore_changes` | Reproducible HMAC passwords, ~16-20x cheaper than Secrets Manager; no plaintext secrets in outputs/state | ✓ Good — secrets never surfaced in plan/state |
| RDS Proxy count-gated behind `enable_rds_proxy` (default false) | Proxy activates ~30 tenants; `try()`-guarded endpoint keeps it zero-cost/zero-resource until enabled | ✓ Good — 0 proxy resources in the default plan |
| Switch default region eu-central-1 → us-east-1 (quick task 260622-opq) | — | ✓ Applied — backend.tf + tfvars now us-east-1 |

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
*Last updated: 2026-06-24 after v1.1 milestone — full milestone evolution review: Current State + Next Milestone Goals added, all shipped requirements Validated, Key Decisions outcomes recorded, Context refreshed (all 11 modules wired, 36-resource plan, us-east-1). **Milestone v1.1 "Complete the shared AWS baseline" shipped** — the full provisioner output contract is satisfied.*
