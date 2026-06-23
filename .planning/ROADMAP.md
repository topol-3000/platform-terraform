# Roadmap: platform-terraform

## Overview

This roadmap covers two milestones. **v1.0** delivered the networking foundation (Phase 1, shipped 2026-06-19). **v1.1** completes the shared AWS baseline by implementing the remaining 10 modules in the locked SEED-001 build order: ecr → ecs → rds-tenant/proxy/control-plane + ssm → efs → acm/alb/route53. Verification is code-complete only: `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` via the offline `make plan-check` gate after every phase — no `terraform apply`, no cloud spend.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Networking module** - VPC, public subnets (no NAT), ALB + task security groups, wired into envs/prod with a clean non-empty plan (completed 2026-06-19)
- [x] **Phase 2: Container platform** - Managed ECR repository (odoo-core) + shared ECS/Fargate cluster, wired into envs/prod with plan-check green (completed 2026-06-23)
- [ ] **Phase 3: Databases and secrets** - Shared tenant RDS (Single-AZ) + RDS Proxy, separate control-plane RDS (Multi-AZ), and SSM SecureString parameters for credentials — all wired and plan-check green
- [ ] **Phase 4: Shared filesystem** - Encrypted EFS with per-AZ mount targets and task-SG-scoped NFS access, wired into envs/prod with plan-check green
- [ ] **Phase 5: TLS and routing** - Wildcard ACM cert, shared ALB (HTTPS, idle_timeout >60s), Route53 hosted zone — all wired with contract outputs exported and plan-check green

## Phase Details

### Phase 1: Networking module

**Goal**: `modules/networking` is fully implemented and wired into `envs/prod`, producing a correct, well-formed, non-empty `terraform plan` that creates the VPC, public subnets, internet gateway/routing, and the ALB and task security groups — exporting the four identifiers (`vpc_id`, `private_subnet_ids`, `task_security_group_id`, `alb_security_group_id`) the provisioner contract requires.
**Depends on**: Nothing (first phase; bootstrap state backend already exists)
**Requirements**: NET-01, NET-02, NET-03, NET-04, NET-05, NET-06, NET-07
**Success Criteria** (what must be TRUE):

  1. `terraform plan` in `envs/prod` is non-empty and shows a VPC, public subnets across ≥2 AZs (with `map_public_ip_on_launch`), an internet gateway, a public route table with `0.0.0.0/0 → IGW`, and the two security groups — and **no NAT gateway** appears in the plan.
  2. The task security group's port-8069 ingress rule references the ALB security group's id as its source (not a CIDR block), confirming tasks on the public subnets are reachable on 8069 only via the ALB.
  3. The ALB security group permits ingress on 80 and 443 from `0.0.0.0/0` with egress open, and every created resource name carries the `var.name_prefix` prefix.
  4. The `module "networking"` call in `envs/prod/main.tf` and its four corresponding outputs in `envs/prod/outputs.tf` are uncommented and resolve — the public subnets are exported under the existing `private_subnet_ids` output name so the provisioner contract is unchanged.
  5. `terraform fmt -check` (recursive) and `terraform validate` both pass for the repo / `envs/prod`.

**Plans**: 2 plans
Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Implement modules/networking (VPC, public subnets, IGW/route table, ALB + task SGs, variables with validation, four outputs)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Wire networking into envs/prod (vars + module call + output re-exports), add offline dummy-AWS make plan, run fmt/validate/non-empty-plan gate

### Phase 2: Container platform

**Goal**: `modules/ecr` and `modules/ecs` are implemented and wired into `envs/prod`, exporting the `ecr_image_uri` and `ecs_cluster_arn` contract outputs, with `make plan-check` passing and the new resources appearing in the plan.
**Depends on**: Phase 1 (networking already wired; ECR and ECS consume no networking outputs but share the same root config and plan gate)
**Requirements**: ECR-01, ECR-02, ECS-01, ECS-02, VER-01
**Success Criteria** (what must be TRUE):

  1. `modules/ecr/main.tf` declares a managed `aws_ecr_repository` for the `odoo-core` image (`name_prefix`-named, scan-on-push, immutable tags, AES256 encryption, untagged-image lifecycle policy) — NOT a pull-through cache (per Phase 2 CONTEXT D-01) — and the module exports `image_uri` as the repository's `repository_url` attribute (no account-id string, no STS data source).
  2. `modules/ecs/main.tf` declares a shared ECS/Fargate cluster named with `var.name_prefix`, and the module exports `cluster_arn`.
  3. The `module "ecr"` and `module "ecs"` calls in `envs/prod/main.tf` are uncommented, and the `ecr_image_uri` and `ecs_cluster_arn` outputs in `envs/prod/outputs.tf` are uncommented and resolve to the correct module attributes.
  4. `make plan-check` passes: `terraform fmt -check`, `terraform validate`, and `terraform plan` all succeed, with the ECR and ECS resources appearing in the plan output (plan is non-empty and includes more resources than Phase 1 alone).

**Plans**: 3 plans
Plans:
**Wave 1** *(parallel — no file overlap)*

- [x] 02-01-PLAN.md — Implement modules/ecr (managed aws_ecr_repository for odoo-core, scan-on-push, immutable tags, AES256, untagged-image lifecycle policy, image_uri output from repository_url)
- [x] 02-02-PLAN.md — Implement modules/ecs (ECS/Fargate cluster, Container Insights, FARGATE + FARGATE_SPOT capacity providers, cluster_arn output)

**Wave 2** *(blocked on Wave 1)*

- [x] 02-03-PLAN.md — Wire ecr/ecs into envs/prod (uncomment module calls + contract outputs, rewrite stale pull-through wording), run offline make plan-check gate

### Phase 3: Databases and secrets

**Goal**: `modules/ssm`, `modules/rds-tenant`, `modules/rds-proxy`, and `modules/rds-control-plane` are implemented and wired into `envs/prod` — SSM holds master credentials as SecureStrings, tenant RDS is Single-AZ with the RDS SG accepting 5432 only from the task SG, control-plane RDS is Multi-AZ and separate from tenant data, and RDS Proxy fronts the tenant instance. All four contract outputs are exported and `make plan-check` is green.
**Depends on**: Phase 1 (networking outputs: `private_subnet_ids`, `task_security_group_id`), Phase 2 (plan gate must stay green)
**Requirements**: RDS-01, RDS-02, RDS-03, RDS-04, SSM-01, SSM-02
**Success Criteria** (what must be TRUE):

  1. `modules/ssm/main.tf` declares `SecureString` parameters for the HMAC salt, RDS master credentials, and tokens; no secret values appear in plaintext in Terraform outputs or state, and the `ssm` call in `envs/prod/main.tf` is uncommented, exporting only parameter names/ARNs (not values).
  2. `modules/rds-tenant/main.tf` declares a Single-AZ PostgreSQL instance (`multi_az = false`) with master credentials sourced from SSM (not hardcoded), a DB subnet group over the baseline subnets, and an RDS security group whose only inbound rule allows port 5432 from the task security group id (no CIDR-based ingress).
  3. `modules/rds-proxy/main.tf` declares an RDS Proxy fronting the tenant RDS instance, authenticating via the SSM-stored secret; the module is present and wired for future activation at ~30 tenants.
  4. `modules/rds-control-plane/main.tf` declares a separate Multi-AZ PostgreSQL instance (`multi_az = true`) with its own subnet group and SG — no resources are shared with the tenant RDS instance.
  5. The `rds_tenant`, `rds_proxy`, and `rds_control_plane` calls in `envs/prod/main.tf` are uncommented using underscore labels (not hyphens), and the `tenant_rds_endpoint`, `rds_proxy_endpoint`, and control-plane endpoint outputs in `envs/prod/outputs.tf` are uncommented and resolve correctly.
  6. `make plan-check` passes: `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` all succeed with the SSM parameters, both RDS instances, and the proxy appearing in the plan.

**Plans**: TBD

### Phase 4: Shared filesystem

**Goal**: `modules/efs` is implemented and wired into `envs/prod`, providing an encrypted shared EFS filesystem with per-AZ mount targets and a security group that accepts NFS (2049) only from the task SG — the `efs_id` contract output is exported and `make plan-check` is green.
**Depends on**: Phase 1 (networking outputs: `private_subnet_ids`, `task_security_group_id`)
**Requirements**: EFS-01, EFS-02
**Success Criteria** (what must be TRUE):

  1. `modules/efs/main.tf` declares an encrypted EFS filesystem with `performance_mode = "generalPurpose"` and `throughput_mode = "elastic"`, at-rest encryption enabled, and an EFS security group whose only inbound rule allows port 2049 from the task security group id (no CIDR-based ingress); no per-tenant access points are created by Terraform.
  2. Mount targets are declared for each subnet from `module.networking.private_subnet_ids`, providing EFS access across all baseline AZs.
  3. The `module "efs"` call in `envs/prod/main.tf` is uncommented, and the `efs_id` output in `envs/prod/outputs.tf` is uncommented and resolves to `module.efs.efs_id`.
  4. `make plan-check` passes: `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` all succeed with the EFS filesystem, mount targets, and security group appearing in the plan.

**Plans**: TBD

### Phase 5: TLS and routing

**Goal**: `modules/acm`, `modules/alb`, and `modules/route53` are implemented and wired into `envs/prod` — a wildcard ACM cert covers `*.{tenant_domain}`, the shared ALB has an HTTPS listener using that cert with idle timeout >60s, and the Route53 hosted zone is declared for `tenant_domain`. The `acm_cert_arn`, `alb_listener_arn`, and `hosted_zone_id` contract outputs are exported and `make plan-check` is green, completing the full provisioner output contract.
**Depends on**: Phase 1 (ALB SG from networking), Phase 3 (plan gate must stay green; SSM wired), Phase 4 (plan gate must stay green)
**Requirements**: ACM-01, ALB-01, DNS-01, TLS-02
**Success Criteria** (what must be TRUE):

  1. `modules/acm/main.tf` declares a wildcard ACM certificate for `*.{tenant_domain}` using DNS validation, with `tenant_domain` validated via a regex `validation` block (guards against empty-string default); the module exports `cert_arn`.
  2. `modules/route53/main.tf` declares a public hosted zone for `tenant_domain` with `tenant_domain` validated in its variable; the module exports `hosted_zone_id`; no per-tenant DNS records are created by Terraform.
  3. `modules/alb/main.tf` declares a shared ALB with an HTTPS listener referencing `var.acm_cert_arn` and `idle_timeout > 60` (Odoo longpoll guard); the module exports `listener_arn`; no per-tenant target groups or host rules are created by Terraform.
  4. The `acm`, `alb`, and `route53` calls in `envs/prod/main.tf` are uncommented, with `acm` called before `alb` (so `module.acm.cert_arn` resolves), and the `acm_cert_arn`, `alb_listener_arn`, and `hosted_zone_id` outputs in `envs/prod/outputs.tf` are uncommented and resolve correctly.
  5. `make plan-check` passes: `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` succeed with all baseline resources (networking + ECR + ECS + RDS + EFS + ACM + ALB + Route53) appearing — the full provisioner output contract is satisfied with all outputs resolvable.
**UI hint**: no

## Progress

**Execution Order:**
Phase 1 complete. Execute Phase 2 → Phase 3 → Phase 4 → Phase 5 in dependency order. Phase 3 and Phase 4 are independent of each other (both depend only on Phase 1 outputs already wired); they may be executed in any order but must each keep the plan gate green.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Networking module | 2/2 | Complete | 2026-06-19 |
| 2. Container platform | 3/3 | Complete   | 2026-06-23 |
| 3. Databases and secrets | 0/TBD | Not started | - |
| 4. Shared filesystem | 0/TBD | Not started | - |
| 5. TLS and routing | 0/TBD | Not started | - |
