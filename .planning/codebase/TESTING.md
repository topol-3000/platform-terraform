# Testing Patterns

**Analysis Date:** 2026-06-19

## Test Framework

**Runner:** None — no automated test framework is present in the repository.

No `*.test.tf`, `*.spec.tf`, Terratest Go files, `pytest`/`python-hcl2` test files, CDKTF snapshot tests, or any other testing infrastructure is detected.

**Validation tooling present:**
- `terraform validate` — syntax and internal consistency check, run via `make validate`
- `terraform fmt -recursive` — formatting check, run via `make fmt`
- `terraform plan` — dry-run against live AWS, run via `make plan`

**Run Commands:**
```bash
make validate   # terraform validate for envs/prod (syntax/type-check only)
make fmt        # terraform fmt -recursive across the whole repo (reformats in-place)
make plan       # terraform plan for envs/prod (requires AWS credentials)
make apply      # terraform apply for envs/prod
make destroy    # terraform destroy for envs/prod
make bootstrap  # terraform init + apply in bootstrap/ (one-time)
make clean      # remove all .terraform/ dirs
```

Override the environment with `ENV=<name>`, e.g. `make plan ENV=staging`.

## Test File Organization

**No test files exist.** All modules are stubs (`STATUS: stub. No resources yet.`).

When tests are added, the Terraform ecosystem convention to follow is:

```
modules/<module-name>/
├── main.tf
├── variables.tf
├── outputs.tf
└── tests/
    └── <module-name>.tftest.hcl   # Terraform native testing (>= 1.6)
```

Or, alternatively, a separate Go test suite using Terratest:

```
tests/
└── <module-name>_test.go
```

## Validation Coverage

**What `terraform validate` checks:**
- HCL syntax validity
- Variable type correctness
- Output references resolve to known values
- Module source paths exist

**What it does NOT check:**
- Whether AWS resources are correctly configured
- Whether IAM policies are sufficient
- Whether security group rules are correct
- Whether resource names or ARNs exist in AWS

## Current State

All 11 resource modules (`modules/networking`, `modules/ecr`, `modules/ecs`, `modules/rds-tenant`, `modules/rds-proxy`, `modules/rds-control-plane`, `modules/efs`, `modules/alb`, `modules/acm`, `modules/route53`, `modules/ssm`) are stubs with no resources. The `bootstrap/` config is the only implemented Terraform root.

`terraform plan` in `envs/prod/` succeeds and produces zero resource changes (all module calls are commented out).

## Recommended Testing Approach When Implementing Modules

**Terraform Native Tests (`.tftest.hcl`):**
- Supported natively since Terraform 1.11 (the version this repo requires)
- No additional tooling needed
- Place test files in `modules/<name>/tests/` or in a top-level `tests/` directory
- Use `run` blocks with `command = plan` for fast validation, `command = apply` for full integration tests

Example pattern to adopt:
```hcl
# modules/networking/tests/networking.tftest.hcl
variables {
  name_prefix = "odoo-saas-test"
}

run "plan_succeeds" {
  command = plan
}

run "vpc_created" {
  command = apply
  # assert blocks here
}
```

**What to test per module (when implemented):**
- `networking`: VPC CIDR, public subnet count, no NAT gateway, security group port rules (8069 only from ALB SG)
- `ecs`: Fargate launch type on cluster
- `rds-tenant`: Single-AZ, engine = postgres, `deletion_protection`
- `rds-control-plane`: Multi-AZ, engine = postgres, `deletion_protection`
- `acm`: Domain matches `*.{tenant_domain}`, DNS validation method
- `alb`: HTTPS listener on 443, idle timeout > 60 (Odoo longpoll ~50s), HTTP-to-HTTPS redirect
- `ssm`: SecureString tier, correct parameter path prefix

## CI/CD Pipeline

No CI configuration (`.github/workflows/`, `.gitlab-ci.yml`, `buildkite.yml`, etc.) is detected. The Makefile is the sole automation interface.

When CI is added, the recommended gate sequence is:
1. `make fmt` — fail if diff (use `terraform fmt -check -recursive`)
2. `make validate` — fail on validation errors
3. `terraform plan` — plan output as PR artifact (requires AWS credentials in CI)
4. Manual approval gate before `make apply`

---

*Testing analysis: 2026-06-19*
