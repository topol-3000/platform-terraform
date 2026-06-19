# Requirements: platform-terraform

**Defined:** 2026-06-19
**Core Value:** `terraform` in `envs/prod` produces a correct, well-formed plan for the shared AWS baseline — the provisioner's dependencies are implemented, wired, and exported.

## v1 Requirements

Milestone scope: **the `networking` module only** (one milestone at a time per the chosen cadence). Verification is code-complete — `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan`. No `terraform apply`.

### Networking

- [ ] **NET-01**: `modules/networking` declares a VPC for the prod baseline (CIDR via variable, `name_prefix`-tagged)
- [ ] **NET-02**: Public subnets across ≥2 AZs (required by the ALB) with `map_public_ip_on_launch`, an internet gateway, and a public route table (`0.0.0.0/0 → IGW`) — **no NAT gateway** (cost decision). Only public subnets are created; no private subnets in this milestone.
- [ ] **NET-03**: ALB security group allowing ingress 80/443 from the internet (`0.0.0.0/0`) and egress out
- [ ] **NET-04**: Task security group accepting port 8069 **only** from the ALB SG (source = ALB SG id, not a CIDR), with egress out
- [ ] **NET-05**: Module declares the required inputs (e.g. `name_prefix`, `vpc_cidr`, `az_count`/`azs`) in `variables.tf` and exports `vpc_id`, `private_subnet_ids` (the public subnets are exposed under this existing contract name so the provisioner contract is unchanged), `task_security_group_id`, `alb_security_group_id` in `outputs.tf`
- [ ] **NET-06**: The `module "networking"` call in `envs/prod/main.tf` and its corresponding `envs/prod/outputs.tf` outputs are uncommented and wired
- [ ] **NET-07**: `terraform fmt -check`, `terraform validate`, and `terraform plan` (in `envs/prod`) all pass and the plan is non-empty (real networking resources appear)

## v2 Requirements

Deferred to future milestones (one module per milestone, SEED-001 build order). Tracked, not in current roadmap.

### Future Modules

- **ECR-01**: `modules/ecr` — pull-through cache from GHCR for the `odoo-core` image
- **ECS-01**: `modules/ecs` — shared Fargate cluster
- **RDS-01**: `modules/rds-tenant` (Single-AZ) — shared tenant PostgreSQL, DB-per-tenant
- **RDS-02**: `modules/rds-proxy` — RDS Proxy fronting the tenant RDS
- **RDS-03**: `modules/rds-control-plane` (Multi-AZ) — control-plane PostgreSQL
- **EFS-01**: `modules/efs` — shared EFS, per-tenant access points created by the adapter
- **ALB-01**: `modules/alb` — shared ALB, host-based routing, idle timeout > 60s
- **ACM-01**: `modules/acm` — wildcard cert for `*.{tenant_domain}`
- **DNS-01**: `modules/route53` — hosted zone for the tenant domain
- **SSM-01**: `modules/ssm` — SecureString params (HMAC salt, RDS master creds)

## Out of Scope

| Feature | Reason |
|---------|--------|
| `terraform apply` to real AWS | This milestone is code-complete only — no cloud spend/creds; verify via validate + non-empty plan |
| NAT gateway | Deliberate cost decision (SEED-001); tasks run on public subnets behind tight SGs. Revisit ~20+ tenants |
| `envs/staging`, multi-region/DR | Not needed until the baseline exists |
| CI/CD, tfsec/checkov, Terratest | Valuable (see CONCERNS.md) but not part of the networking milestone |
| All non-networking modules | Each is its own future milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| NET-01 | Phase 1 | Pending |
| NET-02 | Phase 1 | Pending |
| NET-03 | Phase 1 | Pending |
| NET-04 | Phase 1 | Pending |
| NET-05 | Phase 1 | Pending |
| NET-06 | Phase 1 | Pending |
| NET-07 | Phase 1 | Pending |

**Coverage:**
- v1 requirements: 7 total
- Mapped to phases: 7
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-19*
*Last updated: 2026-06-19 after initial definition*
