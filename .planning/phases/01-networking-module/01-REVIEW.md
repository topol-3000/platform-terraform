---
phase: 01-networking-module
reviewed: 2026-06-19T09:31:14Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - modules/networking/variables.tf
  - modules/networking/main.tf
  - modules/networking/outputs.tf
  - envs/prod/variables.tf
  - envs/prod/main.tf
  - envs/prod/outputs.tf
  - Makefile
  - .gitignore
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: resolved
resolution: "Both warnings (WR-01 plan-check trap hardening, WR-02 root vpc_cidr/azs validation) and IN-03 (stale main.tf header comment) fixed in commit after review. WR-01: trap armed on EXIT INT TERM before override write + defensive rm in plan/apply. IN-01/IN-02/IN-04 accepted as design choices, no action."
---

# Phase 01: Code Review Report

**Reviewed:** 2026-06-19T09:31:14Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

The networking module and its prod wiring are correctly implemented against the locked decisions: VPC `10.0.0.0/16`, `/20` public subnets per AZ via `cidrsubnet(...,4,...)`, no NAT gateway, no private subnets, no `data.aws_availability_zones`, IGW + public route table with the `0.0.0.0/0` route, and — most importantly — the task SG ingress on 8069 uses `security_groups = [aws_security_group.alb.id]` (a SG reference, not a CIDR), which is the load-bearing D-09 guard. Tagging uses provider `default_tags` plus per-resource `Name` only, names are `var.name_prefix`-prefixed, no secrets appear in outputs, and `providers.tf`/`backend.tf` stay clean (D-07 preserved) with the `skip_*` flags isolated to the transient `gate_override.tf`.

No Critical issues. The findings below concern the robustness of the offline `plan-check` gate (the Makefile EXIT-trap cleanup is fragile against an interrupted run) and a few consistency/quality nits. None block shipping the code-complete milestone, but the two Warnings should be fixed before this Makefile target is relied on in CI.

## Warnings

### WR-01: `plan-check` cleanup misses `.terraform.lock.hcl` when init is interrupted, and trap only arms after `cd`

**File:** `Makefile:27-44`
**Issue:** The EXIT trap is the sole cleanup path for the transient `gate_override.tf` plus the local-backend state and `.terraform` dir. Two robustness gaps:

1. The trap runs `rm -rf .terraform .terraform.lock.hcl`, but `.terraform.lock.hcl` is gitignored project-wide and `terraform init -reconfigure` will (re)generate it; removing it on every `plan-check` run silently churns the lock file. More importantly, the trap is registered *inside* the `cd $(ENV_DIR) && ... && trap ... EXIT && terraform init ...` chain. The `cd` and the `printf > gate_override.tf` both happen **before** the trap is armed. If `printf` succeeds but the shell is interrupted (SIGINT/SIGTERM) in the tiny window before `trap` executes — or if `cd` partially fails — `gate_override.tf` can be left behind in `envs/prod`. Because `gate_override.tf` is an `_override.tf` file, a stale copy silently merges `skip_credentials_validation`/dummy creds into the real `provider "aws"` on the *next ordinary* `make plan`/`make apply`, defeating D-07 without any visible diff (the file is gitignored).

2. The trap only fires on `EXIT`, not on `INT`/`TERM`. A Ctrl-C during the long `terraform init`/`plan` may not run the EXIT handler in all shells/Make invocations, leaving the override in place.

**Fix:** Arm the trap for the relevant signals and before creating the file, and drop the lock-file deletion:
```makefile
plan-check: ## Offline gate for $(ENV): fmt -check, validate, non-empty plan
	terraform fmt -check -recursive
	@cd $(ENV_DIR) && \
		trap 'rm -f gate_override.tf terraform.tfstate terraform.tfstate.backup; rm -rf .terraform' EXIT INT TERM && \
		printf '%s\n' \
			'terraform {' '  backend "local" {}' '}' \
			'provider "aws" {' \
			'  skip_credentials_validation = true' \
			'  skip_requesting_account_id  = true' \
			'  skip_metadata_api_check     = true' \
			'  access_key                  = "dummy"' \
			'  secret_key                  = "dummy"' \
			'}' > gate_override.tf && \
		terraform init -reconfigure -input=false >/dev/null && \
		terraform validate && \
		terraform plan -input=false
```
Consider also a defensive `rm -f envs/prod/gate_override.tf` at the top of the `plan` and `apply` recipes so a leaked override can never poison a real run.

### WR-02: Root `azs` / `vpc_cidr` variables carry no validation, so the module's guards are bypassable from the root

**File:** `envs/prod/variables.tf:29-39`
**Issue:** The module (`modules/networking/variables.tf`) correctly validates `vpc_cidr` (`can(cidrhost(...))`) and `azs` (`length >= 2`). But the root passthrough variables that *feed* those inputs have no `validation {}` block. The module-level validation still catches a bad value at plan time (so this is not a Critical correctness hole), but the failure surfaces deep inside the module rather than at the root where the operator set the value, and an empty `azs = []` from a `terraform.tfvars` override produces a confusing module-internal error instead of a clear "at least two AZs" message at the boundary. Since `envs/prod` is the documented operator-facing surface (D-11), the guard should also live there.

**Fix:** Mirror the module validations on the root variables:
```hcl
variable "vpc_cidr" {
  description = "CIDR block for the prod VPC."
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "azs" {
  description = "Availability zones to deploy public subnets into."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two AZs are required (future ALB needs >=2 subnets)."
  }
}
```

## Info

### IN-01: `azs` defaults can drift from `region` with no consistency guard

**File:** `envs/prod/variables.tf:1-5,35-39`
**Issue:** `region` defaults to `eu-central-1` and `azs` defaults to `["eu-central-1a","eu-central-1b"]` as two independent variables. If an operator overrides `region` (e.g. `eu-west-1`) without also overriding `azs`, the VPC/provider land in one region while the subnet AZ names point at another, and the mismatch only surfaces on a real `terraform apply` (an invalid-AZ API error), not in the offline plan gate. This is an accepted consequence of D-04 (explicit AZ list, no `data.aws_availability_zones`), so it is informational only.
**Fix:** Document the coupling on the `azs` description (e.g. "Must be AZs within `var.region`."), or add a cross-field `validation` on `azs` checking each entry `startswith(var.region)` if you want a plan-time guard.

### IN-02: Module subnet `cidrsubnet` is hardwired to `newbits = 4`, coupling subnet size to a `/16` VPC

**File:** `modules/networking/main.tf:21`
**Issue:** `cidrsubnet(var.vpc_cidr, 4, count.index)` yields `/20` only when `vpc_cidr` is a `/16`. The CIDR validation accepts any valid CIDR, so a `/24` `vpc_cidr` would silently produce `/28` subnets (or error if `newbits` exceeds available bits). The plan intentionally left newbits to Claude's discretion (D-02), so hardcoding is acceptable, but the implicit `/16` assumption is undocumented at the variable.
**Fix:** Either note in the `vpc_cidr` description that a `/16` is assumed for the `/20` subnet sizing, or expose an optional `subnet_newbits` variable (default 4) so the relationship is explicit.

### IN-03: Stale module-call comment header is now misleading after wiring

**File:** `envs/prod/main.tf:1-8`
**Issue:** The header still reads "Module calls are commented out until each module is implemented, so that `terraform plan` succeeds (with no resources) on a fresh scaffold." The `networking` module is now uncommented and active, so the blanket statement no longer holds and could mislead a reader into thinking nothing is wired.
**Fix:** Reword to "Module calls below are uncommented as each module lands; downstream modules (ecr/ecs/rds/...) remain commented until implemented."

### IN-04: `region` default in `providers.tf` vs the hardcoded backend region is duplicated, not derived

**File:** `envs/prod/backend.tf:10`, `envs/prod/providers.tf:2`
**Issue:** The S3 backend region is the literal `"eu-central-1"` (it must be — backend blocks cannot use variables), while the provider uses `var.region`. These are two independent sources of truth for the same value; if `var.region` is overridden the provider and the state bucket region diverge. This is an inherent Terraform backend limitation and is already flagged by the `region` variable description ("Must match the state bucket region."), so it is informational only — no action required this milestone.
**Fix:** None required; the existing description note is adequate. Optionally add a comment in `backend.tf` cross-referencing `var.region`.

---

_Reviewed: 2026-06-19T09:31:14Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
