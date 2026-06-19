# platform-terraform

Terraform for the **shared AWS baseline** of the Odoo Entitlements SaaS platform.

This repo provisions the long-lived, fleet-wide resources that the
`provisioner` worker's `AwsDeploymentAdapter` assumes already exist before it
creates *per-tenant* resources (a database, role, ECS service, target group,
EFS access point, etc.). It is the production counterpart to `platform-infra`
(which is local-dev Docker Compose only).

The target architecture is locked in
[`provisioner/.planning/seeds/SEED-001-aws-real-deployment.md`](../provisioner/.planning/seeds/SEED-001-aws-real-deployment.md):
**ECS/Fargate + one shared RDS PostgreSQL (database-per-tenant)**, chosen for
cost-effectiveness and low maintenance.

> **Status:** scaffold. Backend bootstrap is complete; the resource modules are
> stubs with TODOs (see [Roadmap](#roadmap)). `terraform plan` in `envs/prod`
> succeeds and currently produces no resources.

---

## Layout

```
platform-terraform/
├── bootstrap/          # creates the S3 state bucket (local state, run ONCE)
├── envs/
│   └── prod/           # the prod root config — S3 backend, wires modules
└── modules/            # reusable resource modules (stubs for now)
    ├── networking/     # VPC, public subnets (NO NAT gateway), security groups
    ├── ecr/            # ECR pull-through cache for odoo-core (from GHCR)
    ├── ecs/            # shared ECS cluster (Fargate fleet)
    ├── rds-tenant/     # shared tenant RDS (Single-AZ, DB-per-tenant)
    ├── rds-control-plane/ # separate control-plane RDS (Multi-AZ, 99.9% SLA)
    ├── rds-proxy/      # RDS Proxy fronting the tenant RDS
    ├── efs/            # shared EFS (per-tenant access points created by adapter)
    ├── alb/            # shared ALB, host-based routing, idle timeout > 60s
    ├── acm/            # wildcard ACM cert for *.{suffix}
    ├── route53/        # hosted zone for the tenant domain
    └── ssm/            # SSM Parameter Store params (HMAC salt, master creds)
```

Why directory-per-env (`envs/prod`) instead of workspaces: each environment gets
its own backend state key and can diverge freely. Add `envs/staging` later by
copying `envs/prod` and changing the backend `key` + tfvars.

---

## State backend

Remote state lives in **S3** with **native S3 locking** (`use_lockfile = true`,
Terraform ≥ 1.11) — no DynamoDB lock table required.

There is a chicken-and-egg problem: the S3 bucket that holds state must exist
before any config can use the S3 backend. `bootstrap/` solves this — it uses
**local state** and creates the bucket (versioned, encrypted, public access
blocked). You run it once, by hand, before anything else.

---

## Prerequisites

- **Terraform ≥ 1.11** (native S3 state locking). `terraform version` to check.
- **AWS credentials** with rights to create the baseline (an admin/bootstrap
  profile). Configure via `AWS_PROFILE` / `AWS_REGION` or `aws configure`.
- An AWS account and a chosen region (default `eu-central-1` — change in
  `*.tfvars` and `bootstrap`).

---

## Quick start

### 1. Bootstrap the state bucket (once)

```bash
cd bootstrap
terraform init
terraform apply               # creates the S3 state bucket

terraform output state_bucket_name   # note this value
```

S3 bucket names are **globally unique**. The default is `odoo-saas-tfstate`; if
that name is taken, set `-var state_bucket_name=odoo-saas-tfstate-<suffix>` and
use the same value in step 2.

The bootstrap state file (`bootstrap/terraform.tfstate`) is small and not
secret; commit it so the bucket is reproducible, or migrate it into the bucket
later. It is intentionally **not** gitignored.

### 2. Provision the prod baseline

```bash
cd ../envs/prod
cp terraform.tfvars.example terraform.tfvars   # edit: domain, region, etc.

# Point the backend at the bucket from step 1 if you changed the name:
terraform init -backend-config="bucket=odoo-saas-tfstate"

terraform plan
terraform apply
```

A `Makefile` wraps the common commands — `make plan`, `make apply`, `make fmt`,
`make validate` (all operate on `envs/prod`), and `make bootstrap`.

---

## Outputs → provisioner settings

As modules are built, `envs/prod` exports the identifiers the
`AwsDeploymentAdapter` needs as `DEPLOYMENT_ADAPTER=aws` settings (see
`provisioner/src/provisioning_worker/settings.py`):

| Terraform output        | provisioner setting          |
|-------------------------|------------------------------|
| `ecs_cluster_arn`       | `aws_ecs_cluster`            |
| `private_subnet_ids`    | `aws_subnets`                |
| `task_security_group_id`| `aws_security_groups`        |
| `alb_listener_arn`      | `aws_alb_listener_arn`       |
| `tenant_rds_endpoint`   | `aws_shared_rds_endpoint`    |
| `rds_proxy_endpoint`    | `aws_rds_proxy_endpoint`     |
| `efs_id`                | `aws_efs_id`                 |
| `hosted_zone_id`        | `aws_hosted_zone_id`         |
| `acm_cert_arn`          | `aws_acm_cert_arn`           |
| `ecr_image_uri`         | `aws_ecr_image`              |

These are placeholders until the corresponding modules are implemented.

---

## Roadmap

Build order follows SEED-001 §"Next Steps / Prerequisites":

1. ✅ Repo scaffold + S3 state backend (this commit).
2. ☐ `networking` — VPC with a **public** subnet and **no NAT gateway** (cost),
   security groups (task SG accepts 8069 **only** from the ALB SG).
3. ☐ `ecr` — pull-through cache from GHCR for the `odoo-core` image.
4. ☐ `ecs` — shared Fargate cluster.
5. ☐ `rds-tenant` (Single-AZ) + `rds-proxy`; `rds-control-plane` (Multi-AZ).
6. ☐ `efs`, `alb` + `acm` (wildcard), `route53`, `ssm`.

See SEED-001 for the locked decisions, cost-stripping notes, and gotchas
(EFS small-file latency, ALB idle timeout vs Odoo longpoll, cold ECR pull).
