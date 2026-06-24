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

> **Status:** v1.1 complete. All 10 modules are implemented and wired in `envs/prod/main.tf`.
> `terraform plan` produces real resources. No `terraform apply` has been run — this repo
> is code-complete; apply it to provision the actual AWS baseline.

---

## Layout

```
platform-terraform/
├── bootstrap/          # creates the S3 state bucket (local state, run ONCE)
├── envs/
│   └── prod/           # the prod root config — S3 backend, wires modules
├── modules/            # reusable resource modules
│   ├── networking/     # VPC, public subnets (NO NAT gateway), security groups
│   ├── ecr/            # managed ECR repository for odoo-core (CI/CD pushes via GitHub Actions)
│   ├── ecs/            # shared ECS cluster (Fargate fleet)
│   ├── rds-tenant/     # shared tenant RDS (Single-AZ, DB-per-tenant)
│   ├── rds-proxy/      # RDS Proxy fronting the tenant RDS
│   ├── efs/            # shared EFS (per-tenant access points created by adapter)
│   ├── alb/            # shared ALB, host-based routing, idle timeout > 60s
│   ├── acm/            # wildcard ACM cert for *.{suffix}
│   ├── route53/        # hosted zone for the tenant domain
│   └── ssm/            # SSM Parameter Store params (HMAC salt, master creds)
└── docs/               # supplementary guides (e.g. github-actions-ecr-push.md)
```

See [`docs/github-actions-ecr-push.md`](docs/github-actions-ecr-push.md) for the guide
on setting up GitHub Actions to push the `odoo-core` image to the ECR repository.

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
- An AWS account and a chosen region (default `us-east-1` — change in
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

A `Makefile` wraps the common commands (all operate on `envs/prod` unless noted):

| Target | Description |
| ------ | ----------- |
| `make help` | List all targets with descriptions |
| `make bootstrap` | Create the S3 state bucket (run once, local state) |
| `make init` | `terraform init` for the prod env |
| `make plan-check` | **Offline gate:** `fmt -check` + `validate` + non-empty `plan` — no AWS credentials or S3 access required |
| `make plan` | `terraform plan` (real: requires S3 backend + AWS credentials) |
| `make apply` | `terraform apply` |
| `make destroy` | `terraform destroy` |
| `make fmt` | Format all `.tf` files recursively |
| `make validate` | `terraform validate` |
| `make clean` | Remove local `.terraform` dirs |

`make plan-check` is the code-complete verification gate — use it to confirm the config
is well-formed without needing AWS access. It writes a transient `gate_override.tf`
(local backend + stubbed AWS provider), runs the checks, then cleans up.

---

## Configuration

Copy `envs/prod/terraform.tfvars.example` to `envs/prod/terraform.tfvars` (gitignored)
and set the values for your deployment:

| Variable | Default | Notes |
| -------- | ------- | ----- |
| `region` | `us-east-1` | Must match the state bucket region |
| `environment` | `prod` | Used in resource names and tags |
| `project` | `odoo-saas` | Resource name prefix |
| `tenant_domain` | *(required)* | Apex domain, e.g. `saas.example.com` — set before applying route53/acm/alb |
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the VPC |
| `azs` | `[us-east-1a, us-east-1b]` | Availability zones for public subnets |
| `enable_rds_proxy` | `false` | Set `true` at ~30 active tenants |
| `rds_instance_class` | `db.t4g.small` | Applies to the tenant RDS instance. |
| `rds_engine_version` | `16` | PostgreSQL major version |
| `rds_allocated_storage` | `20` | Initial storage in GiB per RDS instance |
| `rds_max_allocated_storage` | `100` | Storage autoscaling ceiling in GiB |

---

## Outputs -> provisioner settings

`envs/prod` exports the identifiers the `AwsDeploymentAdapter` needs as
`DEPLOYMENT_ADAPTER=aws` settings (see
`provisioner/src/provisioning_worker/settings.py`):

| Terraform output             | provisioner setting                    |
| ---------------------------- | -------------------------------------- |
| `ecs_cluster_arn`            | `aws_ecs_cluster`                      |
| `private_subnet_ids`         | `aws_subnets`                          |
| `task_security_group_id`     | `aws_security_groups`                  |
| `vpc_id`                     | (consumed by downstream modules)       |
| `alb_security_group_id`      | (consumed by downstream modules)       |
| `alb_listener_arn`           | `aws_alb_listener_arn`                 |
| `tenant_rds_endpoint`        | `aws_shared_rds_endpoint`              |
| `rds_proxy_endpoint`         | `aws_rds_proxy_endpoint`               |
| `efs_id`                     | `aws_efs_id`                           |
| `hosted_zone_id`             | `aws_hosted_zone_id`                   |
| `acm_cert_arn`               | `aws_acm_cert_arn`                     |
| `ecr_image_uri`              | `aws_ecr_image`                        |

---

## Module status

All modules are implemented and wired in `envs/prod/main.tf` (v1.1 complete):

| Module | Description | Status |
| ------ | ----------- | ------ |
| `networking` | VPC, public subnets (no NAT gateway), security groups | complete |
| `ecr` | Managed ECR repo for odoo-core (IMMUTABLE tags, scan on push) | complete |
| `ecs` | Shared Fargate cluster | complete |
| `ssm` | SSM Parameter Store SecureStrings (HMAC salt, RDS master creds) | complete |
| `rds-tenant` | Shared Single-AZ PostgreSQL; one database per tenant | complete |
| `rds-proxy` | RDS Proxy fronting rds-tenant; gated by `enable_rds_proxy` (activate at ~30 tenants) | complete |
| `efs` | Shared EFS; per-tenant access points created by the provisioner adapter | complete |
| `alb` | Shared ALB, host-based routing, idle timeout > 60 s (Odoo longpoll) | complete |
| `acm` | Wildcard ACM cert for `*.{tenant_domain}` | complete |
| `route53` | Hosted zone for the tenant domain | complete |
