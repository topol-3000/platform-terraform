# External Integrations

**Analysis Date:** 2026-06-19

## AWS Services

All AWS services are provisioned via the `hashicorp/aws ~> 6.0` provider. The region is `eu-central-1` by default (set in `envs/prod/variables.tf` and `bootstrap/variables.tf`).

**Compute:**
- AWS ECS (Elastic Container Service) — Fargate launch type; shared cluster for the multi-tenant Odoo fleet
  - Module: `modules/ecs/` (stub — not yet implemented)
  - Planned output: `ecs_cluster_arn` → consumed by the provisioner `AwsDeploymentAdapter` setting `aws_ecs_cluster`

**Container Registry:**
- AWS ECR (Elastic Container Registry) — pull-through cache for the `odoo-core` image sourced from GitHub Container Registry (GHCR)
  - Module: `modules/ecr/` (stub — not yet implemented)
  - Purpose: eliminates GHCR rate-limit and cold-pull risk for the ~1–2 GB Odoo image
  - Planned output: `ecr_image_uri` → provisioner setting `aws_ecr_image`

**Networking:**
- AWS VPC — single VPC with public subnets, no NAT gateway (cost decision per SEED-001)
  - Module: `modules/networking/` (stub — not yet implemented)
  - Security group constraint: tenant task SG accepts port 8069 only from the ALB SG
  - Planned outputs: `private_subnet_ids` → `aws_subnets`; `task_security_group_id` → `aws_security_groups`

- AWS ALB (Application Load Balancer) — shared ALB with host-based routing (one ALB, routes by `{slug}.{tenant_domain}` Host header)
  - Module: `modules/alb/` (stub — not yet implemented)
  - ALB idle timeout must be > 60s (Odoo longpoll ~50s); health check grace period >= 240s for first-boot init
  - Planned output: `alb_listener_arn` → provisioner setting `aws_alb_listener_arn`

**Databases:**
- AWS RDS PostgreSQL (Tenant) — Single-AZ shared instance, database-per-tenant model
  - Module: `modules/rds-tenant/` (stub — not yet implemented)
  - Sizing note: based on `max_connections`, not number of databases (~5–20 conns/tenant)
  - Planned output: `tenant_rds_endpoint` → provisioner setting `aws_shared_rds_endpoint`

- AWS RDS PostgreSQL (Control Plane) — Separate Multi-AZ instance for platform/control-plane data
  - Module: `modules/rds-control-plane/` (stub — not yet implemented)
  - Isolation requirement: MUST remain separate from tenant RDS; never mix tenant and platform data

- AWS RDS Proxy — Connection pooler fronting the shared tenant RDS
  - Module: `modules/rds-proxy/` (stub — not yet implemented)
  - Activation threshold: ~30 active tenants
  - Known risk: Odoo LISTEN/NOTIFY (bus) may cause connection pinning through the proxy
  - Planned output: `rds_proxy_endpoint` → provisioner setting `aws_rds_proxy_endpoint`

**File Storage:**
- AWS EFS (Elastic File System) — Shared persistent filesystem, mounted at `/var/lib/odoo` in tenant containers
  - Module: `modules/efs/` (stub — not yet implemented)
  - Per-tenant EFS access points created dynamically by the provisioner adapter (not by this repo)
  - Chosen over EBS for durability across task replacement and cross-AZ rescheduling
  - Known risk: small-file latency under `/sessions`
  - Planned output: `efs_id` → provisioner setting `aws_efs_id`

**DNS & TLS:**
- AWS Route53 — Hosted zone for the tenant apex domain
  - Module: `modules/route53/` (stub — not yet implemented)
  - Per-tenant DNS records created dynamically by the provisioner adapter at provision time
  - Planned output: `hosted_zone_id` → provisioner setting `aws_hosted_zone_id`

- AWS ACM (Certificate Manager) — Wildcard TLS certificate for `*.{tenant_domain}`
  - Module: `modules/acm/` (stub — not yet implemented)
  - Custom domain support: additive per-domain SNI cert + ALB host-rule
  - Planned output: `acm_cert_arn` → provisioner setting `aws_acm_cert_arn`

**Secrets & Parameters:**
- AWS SSM Parameter Store — SecureString parameters for HMAC salt, RDS master credentials, and tokens
  - Module: `modules/ssm/` (stub — not yet implemented)
  - Deliberately chosen over AWS Secrets Manager (~16–20x cheaper; HMAC passwords are reproducible)

## Data Storage

**State Backend:**
- AWS S3 — Remote Terraform state bucket
  - Bucket name: `odoo-saas-tfstate` (created by `bootstrap/main.tf`)
  - Key: `prod/baseline.tfstate`
  - Region: `eu-central-1`
  - Encryption: AES256 server-side encryption enabled
  - Versioning: enabled; noncurrent versions expire after 90 days
  - Locking: native S3 lockfile (`use_lockfile = true`) — no DynamoDB table required
  - Public access: fully blocked (all four `block_public_*` settings enabled)
  - Config: `envs/prod/backend.tf`, created by `bootstrap/main.tf`

## External Container Registry (Source Only)

- GitHub Container Registry (GHCR) — Source registry for the `odoo-core` image
  - Not directly provisioned here; accessed via the ECR pull-through cache (`modules/ecr/`)
  - Not a runtime dependency of this Terraform repo; relevant to the ECS task definition

## Authentication & Identity

**AWS Auth:**
- Standard AWS credential chain: `AWS_PROFILE` / `AWS_REGION` environment variables, or `aws configure` profile
- No IAM resources are defined in this repo yet (pending module implementations)
- IAM roles for ECS task execution and RDS access are planned inside `modules/ecs/` and `modules/rds-*/`

## Monitoring & Observability

- Not yet defined — no CloudWatch, X-Ray, or third-party monitoring resources provisioned

## CI/CD & Deployment

**Workflow:**
- Manual via `Makefile` targets (`make bootstrap`, `make plan`, `make apply`)
- No CI pipeline (GitHub Actions, etc.) defined in this repo
- Target deployment platform: AWS `eu-central-1`

## Downstream Consumer

- The `provisioner` service (`AwsDeploymentAdapter` in `provisioner/src/provisioning_worker/settings.py`) consumes the Terraform outputs from `envs/prod/outputs.tf` as runtime settings. This is the primary external integration boundary — Terraform provisions the shared baseline; the provisioner creates per-tenant resources within it.

## Environment Configuration

**Required variables (set in `terraform.tfvars` before applying):**
- `region` — AWS region (default `eu-central-1`)
- `environment` — environment name (default `prod`)
- `project` — project prefix (default `odoo-saas`)
- `tenant_domain` — apex domain (required before building `route53`, `acm`, `alb` modules; no default)

**Secrets location:**
- AWS credentials: outside this repo (environment / `~/.aws/credentials`)
- Runtime secrets (RDS passwords, HMAC salt): planned in SSM Parameter Store via `modules/ssm/`
- `terraform.tfvars`: gitignored (see `.gitignore`); example provided at `envs/prod/terraform.tfvars.example`

## Webhooks & Callbacks

- None — this repo provisions static infrastructure only; no inbound or outbound webhooks are defined here

---

*Integration audit: 2026-06-19*
