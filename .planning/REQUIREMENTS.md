# Requirements: platform-terraform

**Defined:** 2026-06-19 (v1.0) · **Updated:** 2026-06-23 (v1.1)
**Core Value:** `terraform` in `envs/prod` produces a correct, well-formed plan for the shared AWS baseline — the provisioner's dependencies are implemented, wired, and exported.

## v1.1 Requirements — Complete the shared AWS baseline

Milestone scope: **the 10 remaining `modules/*`** (ecr, ecs, rds-tenant, rds-proxy, rds-control-plane, efs, acm, alb, route53, ssm), implemented in the locked SEED-001 build order. Verification stays **code-complete** — `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` via the offline `make plan-check` gate. **No `terraform apply`.**

Each module follows the networking pattern: implement resources → uncomment its call in `envs/prod/main.tf` → wire its `envs/prod/outputs.tf` contract output(s) → keep the plan green. All resources are `name_prefix`-tagged; no module calls another module (all wiring in `envs/prod/main.tf`).

### ECR — container image

- [x] **ECR-01**: `modules/ecr` declares a **managed ECR repository** (`aws_ecr_repository`) for the `odoo-core` image (`name_prefix`-named, scan-on-push, lifecycle policy to expire untagged images). CI/CD pushes the image to ECR — no GHCR runtime dependency, no upstream credential. *(Changed 2026-06-23 from a GHCR pull-through cache: team is moving to AWS-native image storage + private repos; a managed repo also exposes `repository_url` as a resource attribute, keeping the offline `make plan-check` free of account-id/STS data sources. See Phase 2 CONTEXT.md D-01.)*
- [x] **ECR-02**: `ecr` exports `image_uri` (the `repository_url` of the `odoo-core` ECR repo); the `envs/prod` call and the `ecr_image_uri` output are uncommented and wired

### ECS — compute

- [x] **ECS-01**: `modules/ecs` declares a shared **ECS/Fargate cluster** for all tenant tasks (`name_prefix`-named)
- [x] **ECS-02**: `ecs` exports `cluster_arn`; the `envs/prod` call and the `ecs_cluster_arn` output are uncommented and wired

### RDS — databases

- [x] **RDS-01**: `modules/rds-tenant` declares a shared **Single-AZ** PostgreSQL instance (master credentials sourced from SSM, never plaintext), a DB subnet group over the baseline subnets, and an RDS security group accepting 5432 **only** from the task SG (and the proxy SG)
- [x] **RDS-02**: `modules/rds-proxy` declares an **RDS Proxy** fronting the tenant RDS (auth via the SSM-stored secret); present but designed to activate at ~30 active tenants
- [x] **RDS-03**: `modules/rds-control-plane` declares a **separate Multi-AZ** PostgreSQL instance for provisioner control-plane data **only** — isolated from tenant data (blast-radius / 99.9% SLA)
- [x] **RDS-04**: the `rds_tenant`, `rds_proxy`, and `rds_control_plane` calls and the `tenant_rds_endpoint` / `rds_proxy_endpoint` (and control-plane endpoint) outputs are uncommented and wired

### EFS — shared filestore

- [ ] **EFS-01**: `modules/efs` declares a shared **encrypted EFS filesystem** with a mount target per AZ and an EFS security group accepting NFS (2049) **only** from the task SG; per-tenant **access points are NOT created by Terraform** (the provisioner adapter creates them at provision time)
- [ ] **EFS-02**: `efs` exports `efs_id`; the `envs/prod` call and the `efs_id` output are uncommented and wired

### TLS & routing — ACM, ALB, Route53

- [ ] **ACM-01**: `modules/acm` declares a **wildcard ACM certificate** for `*.{tenant_domain}` using DNS validation
- [ ] **ALB-01**: `modules/alb` declares a shared **ALB** with an HTTPS listener using the ACM cert and **idle timeout > 60s** (Odoo longpoll ~50s); per-tenant target groups / host rules are added by the adapter, not Terraform
- [ ] **DNS-01**: `modules/route53` declares a public **hosted zone** for `tenant_domain`; per-tenant DNS records are added by the adapter
- [ ] **TLS-02**: the `acm`, `alb`, and `route53` calls and the `acm_cert_arn` / `alb_listener_arn` / `hosted_zone_id` outputs are uncommented and wired

### SSM — secrets

- [x] **SSM-01**: `modules/ssm` declares Parameter Store **SecureString** parameters for the HMAC salt, RDS master credentials, and tokens; secrets are **never** exposed in plaintext outputs or state
- [x] **SSM-02**: the `ssm` call is uncommented and wired, exporting only non-secret references (parameter names/ARNs)

### Verification (milestone-wide)

- [x] **VER-01**: After each module lands, `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` in `envs/prod` all pass via the offline `make plan-check` gate — no `terraform apply`

## Completed — v1.0 Networking (shipped)

- [x] **NET-01**: `modules/networking` declares a VPC for the prod baseline (CIDR via variable, `name_prefix`-tagged)
- [x] **NET-02**: Public subnets across ≥2 AZs with `map_public_ip_on_launch`, an internet gateway, and a public route table (`0.0.0.0/0 → IGW`) — **no NAT gateway**
- [x] **NET-03**: ALB security group allowing ingress 80/443 from the internet and egress out
- [x] **NET-04**: Task security group accepting 8069 **only** from the ALB SG (source = ALB SG id), with egress out
- [x] **NET-05**: Module declares inputs in `variables.tf` and exports `vpc_id`, `private_subnet_ids`, `task_security_group_id`, `alb_security_group_id`
- [x] **NET-06**: The `networking` call in `envs/prod/main.tf` and its `envs/prod/outputs.tf` outputs are uncommented and wired
- [x] **NET-07**: `fmt -check`, `validate`, and a non-empty `plan` all pass (9 resources)

## Out of Scope

| Feature | Reason |
|---------|--------|
| `terraform apply` to real AWS | This milestone is code-complete only — no cloud spend; verify via validate + non-empty plan |
| Per-tenant resources (databases, ECS services, EFS access points, target groups, DNS records) | Created at runtime by the provisioner `AwsDeploymentAdapter`, not by this baseline Terraform |
| NAT gateway | Deliberate cost decision (SEED-001); tasks run on public subnets behind tight SGs. Revisit ~20+ tenants |
| `envs/staging`, multi-region/DR | Not needed until the baseline exists |
| CI/CD, tfsec/checkov, Terratest | Valuable (see CONCERNS.md) but not part of this milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ECR-01 | Phase 2 | Complete |
| ECR-02 | Phase 2 | Complete |
| ECS-01 | Phase 2 | Complete |
| ECS-02 | Phase 2 | Complete |
| VER-01 | Phase 2 (cross-cutting: all phases) | Complete |
| RDS-01 | Phase 3 | Complete |
| RDS-02 | Phase 3 | Complete |
| RDS-03 | Phase 3 | Complete |
| RDS-04 | Phase 3 | Complete |
| SSM-01 | Phase 3 | Complete |
| SSM-02 | Phase 3 | Complete |
| EFS-01 | Phase 4 | Pending |
| EFS-02 | Phase 4 | Pending |
| ACM-01 | Phase 5 | Pending |
| ALB-01 | Phase 5 | Pending |
| DNS-01 | Phase 5 | Pending |
| TLS-02 | Phase 5 | Pending |

**Coverage:**
- v1.1 requirements: 17 total (ECR x2, ECS x2, RDS x4, EFS x2, TLS/routing x4, SSM x2, VER x1)
- Mapped to phases: 17/17 (100%) — Phase 2: 5, Phase 3: 6, Phase 4: 2, Phase 5: 4

---
*Requirements defined: 2026-06-19 (v1.0)*
*Last updated: 2026-06-23 — v1.1 traceability filled by roadmapper*
