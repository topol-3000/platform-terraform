# Technology Stack

**Analysis Date:** 2026-06-19

## Languages

**Primary:**
- HCL (HashiCorp Configuration Language) - All Terraform configuration (`.tf` files throughout `bootstrap/`, `envs/`, `modules/`)

**Secondary:**
- Makefile (GNU Make) - Workflow automation via `Makefile`

## Runtime

**Environment:**
- Terraform >= 1.11.0 (required_version constraint in `envs/prod/versions.tf` and `bootstrap/versions.tf`)
- Native S3 state locking via `use_lockfile = true` (Terraform 1.11+ feature, eliminates DynamoDB dependency)

**Package Manager:**
- None (Terraform providers are resolved via the Terraform provider registry at `registry.terraform.io`)
- Lockfile: `.terraform.lock.hcl` (generated on `terraform init`, gitignored per `/.gitignore`)

## Frameworks

**Core:**
- Terraform >= 1.11.0 - Infrastructure-as-code orchestration

**Build/Dev:**
- GNU Make - Workflow wrapper (`Makefile`); targets: `bootstrap`, `init`, `plan`, `apply`, `destroy`, `fmt`, `validate`, `clean`

**Testing:**
- Not applicable — no automated test framework detected. Validation is done via `terraform validate` and `terraform plan`.

## Key Dependencies

**Critical:**
- `hashicorp/aws` ~> 6.0 (AWS provider) - Declared in `envs/prod/versions.tf` and `bootstrap/versions.tf`. All AWS resource provisioning goes through this provider.

## Configuration

**Environment:**
- Per-environment tfvars: copy `envs/prod/terraform.tfvars.example` → `envs/prod/terraform.tfvars` (gitignored)
- Key variables: `region` (default `eu-central-1`), `environment` (default `prod`), `project` (default `odoo-saas`), `tenant_domain` (must be set before building route53/acm/alb modules)
- AWS credentials: configured externally via `AWS_PROFILE`, `AWS_REGION`, or `aws configure` — not stored in this repo

**Build:**
- `bootstrap/versions.tf` — local-state bootstrap config (provider + version constraints)
- `envs/prod/versions.tf` — prod root config provider + version constraints
- `envs/prod/backend.tf` — S3 remote backend declaration
- `envs/prod/providers.tf` — AWS provider config with default tags

## Platform Requirements

**Development:**
- Terraform >= 1.11.0 installed locally
- AWS credentials configured (admin/bootstrap privileges for first run)
- GNU Make (optional, wraps common commands)

**Production:**
- Deployment target: AWS (`eu-central-1` default region)
- State backend: S3 bucket `odoo-saas-tfstate` (created by `bootstrap/`)
- No CI/CD pipeline defined in this repo (manual `make apply` workflow)

## Project Identity

- Project name: `odoo-saas`
- Platform: SaaS multi-tenant Odoo platform on AWS
- Resource naming convention: `{project}-{environment}` prefix, e.g. `odoo-saas-prod`
- All resources tagged: `Project=odoo-saas`, `Environment=<env>`, `ManagedBy=terraform`, `Repo=platform-terraform`

---

*Stack analysis: 2026-06-19*
