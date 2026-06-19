# Phase 1: Networking module - Context

**Gathered:** 2026-06-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `modules/networking` (VPC, public subnets, internet gateway + public route table, ALB security group, task security group) and wire it into `envs/prod` so that `terraform plan` produces a correct, non-empty plan. Public subnets only — **no NAT gateway**, no private subnets. Verification is **code-complete only**: `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` in `envs/prod`. No `terraform apply`, no AWS spend.

Covers requirements NET-01 through NET-07 (see REQUIREMENTS.md).
</domain>

<decisions>
## Implementation Decisions

### CIDR & Subnets
- **D-01:** VPC CIDR is `10.0.0.0/16`.
- **D-02:** Public subnets are `/20`, derived with `cidrsubnet(var.vpc_cidr, 4, count.index)` (or `for_each` over AZs) — ~4k IPs each, room to grow.
- **D-03:** Only public subnets are created. They are exported under the existing `private_subnet_ids` output name so the provisioner contract (`envs/prod/outputs.tf`) is unchanged. (Carried forward from PROJECT.md.)

### Availability Zones
- **D-04:** AZs come from an explicit **list variable** `azs` (e.g. `variable "azs" { type = list(string) }`), default `["eu-central-1a", "eu-central-1b"]`. **No `data.aws_availability_zones` data source** — this keeps `terraform plan` runnable without live AWS API calls.
- **D-05:** One public subnet per AZ in the list (≥2 AZs, required by the future ALB).

### Plan-without-credentials (code-complete verification)
- **D-06:** `make plan` (and any plan target) exports **dummy AWS credentials** + region inline, e.g. `AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy AWS_REGION=eu-central-1 terraform plan`. Because there are no data sources and no prior state to refresh, the AWS provider initializes but makes no real API calls, so the plan succeeds offline.
- **D-07:** Do **not** add `skip_credentials_validation` / `skip_requesting_account_id` / `skip_metadata_api_check` to `providers.tf` — keep the provider config clean for real applies later. The dummy-env approach lives only in the Makefile.

### Security Groups
- **D-08:** ALB security group: ingress on **both 80 and 443** from `0.0.0.0/0`; egress allow-all (`0.0.0.0/0`, all protocols).
- **D-09:** Task security group: ingress on port **8069 only**, source = the **ALB SG id** (security-group reference, NOT a CIDR). Egress allow-all. (Carried forward — this is the only thing protecting public-subnet tasks from direct internet exposure.)
- **D-10:** Allow-all egress accepted for now (tasks need outbound to ECR/SSM/internet with no NAT). Egress tightening deferred — see Deferred Ideas.

### Variable Defaults & Module Interface
- **D-11:** Key inputs carry **prod-sensible defaults in `envs/prod`** so `make plan` runs with zero `terraform.tfvars` editing.
- **D-12:** Implement the **full module variable set now** in `modules/networking/variables.tf`: at minimum `name_prefix`, `vpc_cidr`, `azs` (plus subnet-sizing newbits if parameterized), each with a `validation` block where sensible (e.g. CIDR format, `length(azs) >= 2`).
- **D-13:** Every resource name and tag uses `var.name_prefix` (e.g. `"${var.name_prefix}-vpc"`). All wiring stays in `envs/prod/main.tf` — the module calls no other modules.

### Claude's Discretion
- Subnet `for_each` vs `count` implementation style.
- Whether to expose subnet newbits/sizing as a variable or hardcode `/20` via `cidrsubnet(..., 4, ...)`.
- Exact resource ordering and use of `aws_route` vs inline routes in `aws_route_table`.
- Tag map composition beyond `name_prefix` (default_tags already set in `providers.tf`).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & project scope
- `.planning/REQUIREMENTS.md` — NET-01..NET-07, the locked v1 scope and out-of-scope boundaries
- `.planning/PROJECT.md` — Core value, constraints (no NAT, name_prefix, code-complete verification), key decisions

### Existing architecture & conventions (from codebase map)
- `.planning/codebase/ARCHITECTURE.md` — root-module composition, the `name_prefix` abstraction, anti-patterns (no module-to-module calls, no hardcoded names, no plaintext secrets), provisioner output contract
- `.planning/codebase/CONVENTIONS.md` — module interface / variable / output naming conventions to match
- `.planning/codebase/CONCERNS.md` — networking-specific risk: public-subnet tasks must allow only 8069 from the ALB SG; pre-declare expected variables before uncommenting module calls

### Files to implement / edit
- `modules/networking/main.tf`, `modules/networking/variables.tf`, `modules/networking/outputs.tf` — the module (currently stubs)
- `envs/prod/main.tf` — uncomment + wire the `module "networking"` call (NET-06)
- `envs/prod/outputs.tf` — uncomment the networking-sourced outputs (`private_subnet_ids`, `task_security_group_id`, and add `vpc_id` / `alb_security_group_id` as needed)
- `envs/prod/variables.tf` — add `vpc_cidr`, `azs` (with prod defaults)
- `envs/prod/providers.tf` — leave provider clean (D-07); reference only
- `Makefile` — add dummy-AWS-env to the plan target (D-06)

### External (architecture source of truth, may be outside this repo)
- `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md` — the locked target architecture (referenced by README); not present in this repo tree, treat README §Roadmap + ARCHITECTURE.md as the in-repo proxy if unavailable
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `local.name_prefix = "${var.project}-${var.environment}"` (= `odoo-saas-prod`) in `envs/prod/main.tf` — pass as the module's `name_prefix`.
- `default_tags` block already set in `envs/prod/providers.tf` (Project/Environment/ManagedBy/Repo) — resources inherit tags; module need only add Name-style tags.
- The commented `module "networking"` block and commented outputs in `envs/prod/main.tf` / `outputs.tf` already define the expected interface (output names like `private_subnet_ids`, `task_security_group_id`).

### Established Patterns
- Modules receive `name_prefix` and expose typed outputs consumed only by the root config (no cross-module references).
- `terraform fmt -recursive` and `terraform validate` are wrapped by the Makefile (`make fmt`, `make validate`); plan/apply operate on `envs/prod`.
- Resource names are `"${var.name_prefix}-<thing>"`; never hardcoded.

### Integration Points
- Module outputs flow into `envs/prod/outputs.tf`, which is the typed contract to the provisioner `AwsDeploymentAdapter`. Output names must match the contract: `private_subnet_ids`, `task_security_group_id` (plus `vpc_id`, `alb_security_group_id` for downstream modules).
</code_context>

<specifics>
## Specific Ideas

- VPC `10.0.0.0/16`, `/20` public subnets, AZs `[eu-central-1a, eu-central-1b]` as defaults.
- `make plan` must succeed offline via dummy AWS env vars — this is the concrete code-complete gate.
- Task SG rule must reference the ALB SG id, not a CIDR — verifiable in the plan output.
</specifics>

<deferred>
## Deferred Ideas

- **Egress tightening** — restrict task SG egress to 443 (HTTPS to ECR/SSM/AWS APIs) instead of allow-all. Deferred to a future hardening pass; allow-all now to avoid breaking outbound before the ecr/ecs/ssm modules exist.
- **VPC endpoints (S3/ECR/SSM/interface)** — cleaner no-NAT outbound path than public IPs; belongs in a later networking-hardening or ecr/ecs phase.
- **Private subnets** — only relevant when RDS lands (future milestone); not created now.
- **Provider lock file + tfsec/CI** — repo-wide concerns from CONCERNS.md, not part of this module milestone.

### Reviewed Todos (not folded)
None — no pending todos matched this phase.
</deferred>

---

*Phase: 1-networking-module*
*Context gathered: 2026-06-19*
