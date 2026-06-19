# Codebase Structure

**Analysis Date:** 2026-06-19

## Directory Layout

```
platform-terraform/
├── bootstrap/                  # One-shot S3 state bucket provisioner (local state)
│   ├── main.tf                 # S3 bucket + versioning + encryption + lifecycle
│   ├── outputs.tf              # state_bucket_name, state_bucket_arn, region
│   ├── variables.tf            # region, state_bucket_name, noncurrent_version_expiration_days
│   └── versions.tf             # terraform >= 1.11, aws ~> 6.0, provider block
│
├── envs/
│   └── prod/                   # Production root config — S3 backend, wires all modules
│       ├── backend.tf          # S3 backend: bucket, key=prod/baseline.tfstate, use_lockfile=true
│       ├── main.tf             # locals { name_prefix }, module calls (commented until implemented)
│       ├── outputs.tf          # Re-exports module outputs → provisioner AwsDeploymentAdapter
│       ├── providers.tf        # aws provider + default_tags
│       ├── variables.tf        # region, environment, project, tenant_domain
│       └── versions.tf         # terraform >= 1.11, aws ~> 6.0
│
├── modules/
│   ├── networking/             # VPC, public subnet (no NAT), security groups
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: vpc_id, private_subnet_ids, task_security_group_id)
│   │   └── variables.tf        # name_prefix
│   ├── ecr/                    # ECR pull-through cache for odoo-core from GHCR
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: image_uri)
│   │   └── variables.tf        # name_prefix
│   ├── ecs/                    # Shared Fargate cluster
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: cluster_arn)
│   │   └── variables.tf        # name_prefix
│   ├── rds-tenant/             # Shared Single-AZ PostgreSQL, database-per-tenant
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: endpoint)
│   │   └── variables.tf        # name_prefix (subnet_ids added at call site in envs/prod)
│   ├── rds-proxy/              # RDS Proxy fronting rds-tenant
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: endpoint)
│   │   └── variables.tf        # name_prefix
│   ├── rds-control-plane/      # Separate Multi-AZ PostgreSQL for control-plane data
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf        # name_prefix
│   ├── efs/                    # Shared EFS; per-tenant access points created by adapter
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: efs_id)
│   │   └── variables.tf        # name_prefix
│   ├── alb/                    # Shared ALB, host-based routing
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: listener_arn)
│   │   └── variables.tf        # name_prefix, acm_cert_arn (added at call site)
│   ├── acm/                    # Wildcard ACM cert for *.{tenant_domain}
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: cert_arn)
│   │   └── variables.tf        # name_prefix, tenant_domain (added at call site)
│   ├── route53/                # Hosted zone for tenant domain
│   │   ├── main.tf
│   │   ├── outputs.tf          # (planned: hosted_zone_id)
│   │   └── variables.tf        # name_prefix, tenant_domain (added at call site)
│   └── ssm/                    # SSM Parameter Store SecureStrings
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf        # name_prefix
│
├── .planning/
│   └── codebase/               # GSD codebase analysis documents
│       ├── ARCHITECTURE.md
│       ├── STACK.md
│       └── STRUCTURE.md
│
├── Makefile                    # Dev convenience: bootstrap, init, plan, apply, fmt, validate
├── README.md                   # Project overview, layout, state backend docs, output→provisioner table
└── .gitignore
```

## Directory Purposes

**`bootstrap/`:**
- Purpose: One-time creation of the S3 bucket that all other Terraform configs use as their remote state backend
- Contains: AWS S3 bucket resource with versioning, encryption, public access block, and lifecycle rules
- Key files: `bootstrap/main.tf`, `bootstrap/versions.tf`
- Special: Uses LOCAL state (not S3). The resulting `bootstrap/terraform.tfstate` is committed to git.

**`envs/prod/`:**
- Purpose: The production root Terraform configuration. Composes all shared modules and exports their outputs as the provisioner adapter's configuration contract.
- Contains: Provider config, S3 backend config, variable declarations, module instantiation, output definitions
- Key files: `envs/prod/main.tf`, `envs/prod/outputs.tf`, `envs/prod/backend.tf`
- Note: Directory-per-env pattern chosen over workspaces — each env gets its own backend state key and can diverge freely. Add staging by copying this directory and changing `backend.tf key` and tfvars.

**`modules/*/`:**
- Purpose: Reusable, independently deployable resource modules, one per AWS service domain
- Contains: `main.tf` (resources), `variables.tf` (inputs), `outputs.tf` (exports)
- Key pattern: Every module exposes `var.name_prefix` as its sole required input. Additional inputs specific to a module are declared in `variables.tf` and supplied from `envs/prod/main.tf`.
- Current state: All modules are stubs — resource blocks and outputs are commented out pending SEED-001 implementation.

**`.planning/codebase/`:**
- Purpose: GSD codebase map documents consumed by `/gsd-plan-phase` and `/gsd-execute-phase`
- Generated: Yes (by gsd-map-codebase agent)
- Committed: Yes

## Key File Locations

**Entry Points:**
- `bootstrap/main.tf`: Bootstrap S3 state bucket — run once before anything else
- `envs/prod/main.tf`: Production root config — primary apply target

**State Backend:**
- `envs/prod/backend.tf`: Declares S3 backend (bucket `odoo-saas-tfstate`, key `prod/baseline.tfstate`, `use_lockfile = true`)
- `bootstrap/main.tf`: Creates the S3 bucket referenced in `backend.tf`

**Provisioner Contract:**
- `envs/prod/outputs.tf`: All outputs that `AwsDeploymentAdapter` reads as runtime settings

**Provider & Version Constraints:**
- `envs/prod/versions.tf`: `terraform >= 1.11`, `aws ~> 6.0`
- `bootstrap/versions.tf`: Same constraints + inline `provider "aws"` block

**Module Inputs:**
- `modules/*/variables.tf`: Every module requires at minimum `name_prefix` (string)

**Developer Workflow:**
- `Makefile`: Wraps `terraform init/plan/apply/destroy/fmt/validate` and `bootstrap`

## Naming Conventions

**Directories:**
- Environments: `envs/{env-name}/` — lowercase, matches `var.environment` value (e.g. `envs/prod/`)
- Modules: `modules/{service-domain}/` — lowercase kebab-case matching the AWS service (e.g. `modules/rds-tenant/`, `modules/rds-control-plane/`)

**Files:**
- Every Terraform config (bootstrap and envs) uses the standard four-file layout: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- `envs/prod/` adds `backend.tf` and `providers.tf` (separated from `versions.tf`)
- No `.tfvars` files are committed — the README references a `terraform.tfvars.example` for the prod env

**Resources:**
- All resource names must be prefixed with `var.name_prefix` (resolved to `"odoo-saas-prod"` in production)
- Local values use `snake_case` (e.g. `name_prefix`, `state_bucket_name`)
- Module call names in `envs/prod/main.tf` use `snake_case` matching the module directory with hyphens replaced: `module "rds_tenant"`, `module "rds_control_plane"`

**Variables:**
- `snake_case` throughout
- Standard cross-cutting variables: `name_prefix` (modules), `region`, `environment`, `project` (envs)

**Outputs:**
- `snake_case`
- Output descriptions include the provisioner setting name they feed (e.g. `-> provisioner aws_ecs_cluster`)

**Tags:**
- Applied via `default_tags` on the AWS provider: `Project`, `Environment`, `ManagedBy=terraform`, `Repo=platform-terraform`

## Where to Add New Code

**New environment (e.g. staging):**
- Copy `envs/prod/` → `envs/staging/`
- Change `backend.tf` key to `staging/baseline.tfstate`
- Set environment-specific values in `terraform.tfvars`
- No changes to `modules/` needed

**New module:**
- Create `modules/{service-name}/main.tf`, `variables.tf`, `outputs.tf`
- Add `variable "name_prefix"` as the first and required variable in `variables.tf`
- Add module stub comment block at top of `main.tf` following the existing pattern:
  ```hcl
  # Module: {name}
  # Purpose: {one-line description}
  #
  # SEED-001 note: {relevant constraint or gotcha}
  #
  # STATUS: stub. No resources yet.
  # TODO: implement {description}
  ```
- Wire it in `envs/prod/main.tf` with a commented-out module block at the appropriate build-order step
- Add the corresponding output block in `envs/prod/outputs.tf` with a comment mapping to the provisioner setting

**Implementing an existing stub module:**
- Edit `modules/{name}/main.tf` — add resources
- Uncomment and fill `modules/{name}/outputs.tf` — add output values
- Uncomment the module call in `envs/prod/main.tf` and supply all required variables
- Uncomment the corresponding outputs in `envs/prod/outputs.tf`
- Run `make validate && make plan` to verify

**Adding a variable to a module:**
- Add to `modules/{name}/variables.tf`
- Supply the value in the module call block in `envs/prod/main.tf`

**Shared secrets / parameters:**
- Add to `modules/ssm/main.tf` as `aws_ssm_parameter` resources with `type = "SecureString"`
- Export the parameter path (not value) from `modules/ssm/outputs.tf`

## Special Directories

**`bootstrap/`:**
- Generated: No (handcrafted, run once)
- Committed: Yes — including `bootstrap/terraform.tfstate` (small, non-secret)
- Warning: Do not add this to `.gitignore`. The state file records the S3 bucket and must be reproducible.

**`.terraform/` (gitignored):**
- Purpose: Local provider cache and module downloads created by `terraform init`
- Generated: Yes
- Committed: No (`make clean` removes all `.terraform/` dirs)

**`.planning/`:**
- Purpose: GSD planning documents (codebase maps, phase plans, seeds)
- Generated: Yes (by GSD agent commands)
- Committed: Yes

---

*Structure analysis: 2026-06-19*
