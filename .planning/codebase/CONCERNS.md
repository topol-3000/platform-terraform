# Codebase Concerns

**Analysis Date:** 2026-06-19

---

## Tech Debt

**All 10 resource modules are unimplemented stubs:**
- Issue: Every module under `modules/` contains only a comment header and a `# TODO` line. No Terraform resources, data sources, or locals exist in any module. `terraform plan` produces zero resources.
- Files: `modules/networking/main.tf`, `modules/ecr/main.tf`, `modules/ecs/main.tf`, `modules/rds-tenant/main.tf`, `modules/rds-proxy/main.tf`, `modules/rds-control-plane/main.tf`, `modules/efs/main.tf`, `modules/alb/main.tf`, `modules/acm/main.tf`, `modules/route53/main.tf`, `modules/ssm/main.tf`
- Impact: No AWS infrastructure exists. The `provisioner` service's `AwsDeploymentAdapter` has no shared baseline to operate against; all provisioner outputs (ECS ARN, subnet IDs, ALB listener, RDS endpoint, EFS ID, etc.) remain commented out in `envs/prod/outputs.tf`.
- Fix approach: Implement modules in SEED-001 build order (networking → ecr → ecs → rds-tenant + rds-proxy + rds-control-plane → efs + acm + alb + route53 + ssm). Uncomment each corresponding module call in `envs/prod/main.tf` and output in `envs/prod/outputs.tf` as each lands.

**All `envs/prod` module calls are commented out:**
- Issue: `envs/prod/main.tf` contains all 10 module invocations as commented blocks. They reference outputs that do not yet exist (e.g., `module.networking.private_subnet_ids`).
- Files: `envs/prod/main.tf`
- Impact: `terraform plan` succeeds vacuously. Any CI check on plan output will always report "no changes" even after a breaking edit to a stub.
- Fix approach: Uncomment each module block as its `main.tf` gains real resources. Consider a CI check that validates `plan` output is non-empty once the first module is implemented.

**Bootstrap state file not committed:**
- Issue: The `.gitignore` includes a specific exception (`!bootstrap/terraform.tfstate`) to allow committing the bootstrap state file so the S3 bucket is reproducible. The README and bootstrap README both instruct committing it. The file is currently absent from the repo.
- Files: `bootstrap/terraform.tfstate` (absent), `bootstrap/.gitignore` exception, `bootstrap/README.md`
- Impact: If the bootstrap is re-run by a different operator without the existing state file, Terraform will attempt to create a new S3 bucket, which will conflict or produce a second bucket with a suffix. The bucket's `prevent_destroy = true` lifecycle guard is also lost without state.
- Fix approach: Run `cd bootstrap && terraform init && terraform apply`, then commit `bootstrap/terraform.tfstate` and `bootstrap/terraform.tfstate.backup`.

**No provider lock files committed:**
- Issue: No `.terraform.lock.hcl` file exists for either `bootstrap/` or `envs/prod/`. Lock files are gitignored (`/.terraform.lock.hcl` is in `.gitignore` at root).
- Files: `.gitignore`
- Impact: `terraform init` will resolve the AWS provider (`~> 6.0`) to different minor versions across machines or CI runs, leading to inconsistent plans and potential drift between environments.
- Fix approach: Remove `.terraform.lock.hcl` from `.gitignore` (or add exceptions `!bootstrap/.terraform.lock.hcl` and `!envs/prod/.terraform.lock.hcl`). Run `terraform init` in each config, then commit the generated lock files.

**`rds-tenant` variable stub is missing required inputs:**
- Issue: `modules/rds-tenant/variables.tf` declares only `name_prefix`. The `envs/prod/main.tf` already shows that `subnet_ids` will be a required input (passed as `module.networking.private_subnet_ids`), but it is not declared in the module's variable file.
- Files: `modules/rds-tenant/variables.tf`, `envs/prod/main.tf` (line 35)
- Impact: When the module is implemented, `terraform plan` will fail with an "unsupported argument" error unless `subnet_ids` (and other expected inputs like `vpc_id`, `db_instance_class`, `engine_version`) are added to `variables.tf` first.
- Fix approach: Pre-declare all expected inputs in `modules/rds-tenant/variables.tf` before implementing the resource body.

**`modules/acm` and `modules/route53` are missing `tenant_domain` variable:**
- Issue: Both modules will require `tenant_domain` as an input (as shown by the `envs/prod/main.tf` commented calls at lines 57 and 68), but their `variables.tf` files only declare `name_prefix`.
- Files: `modules/acm/variables.tf`, `modules/route53/variables.tf`, `envs/prod/main.tf`
- Impact: Same as above — `terraform plan` will fail when modules are uncommented without the variable declared.
- Fix approach: Add `variable "tenant_domain"` with a validation block (see Security Considerations below) to both module variable files ahead of implementation.

**`modules/alb` is missing `acm_cert_arn` variable:**
- Issue: `envs/prod/main.tf` line 63 shows `acm_cert_arn = module.acm.cert_arn` as an input to `module.alb`, but `modules/alb/variables.tf` only declares `name_prefix`.
- Files: `modules/alb/variables.tf`, `envs/prod/main.tf`
- Impact: The ALB module will fail `terraform plan` when uncommented unless the variable is declared.
- Fix approach: Pre-declare `acm_cert_arn` in `modules/alb/variables.tf`.

**S3 state backend bucket name is hardcoded in `envs/prod/backend.tf`:**
- Issue: `backend.tf` hardcodes `bucket = "odoo-saas-tfstate"` and `region = "eu-central-1"`. Backend blocks cannot use variables or locals in Terraform.
- Files: `envs/prod/backend.tf`
- Impact: Copying `envs/prod` to create `envs/staging` will require manually editing the backend block — easy to forget and cause both environments to share the same state key if only the `key` argument is not also changed. There is also a mismatch risk if the bootstrap was applied with a custom bucket suffix.
- Fix approach: Document the override procedure clearly in `envs/prod/backend.tf` (a comment is already present) and add a validation step to the Makefile `init` target that echoes the resolved bucket name. For multi-env support, use partial backend configuration via `-backend-config` files per env.

**Only one environment (`prod`) exists; no staging path:**
- Issue: `envs/` contains only `prod/`. The README mentions copying to `envs/staging` but no template or automation exists.
- Files: `envs/`
- Impact: No safe environment to validate module implementations before applying to prod. All first-time resource deployments will go directly to production.
- Fix approach: Add `envs/staging/` as a copy of `envs/prod/` with a different backend `key` and cheaper instance sizes in tfvars. Create a `make init ENV=staging` example in the README.

---

## Security Considerations

**`tenant_domain` variable has an empty-string default and no validation:**
- Risk: If `tenant_domain` is left as `""` (the default) when the `acm`, `alb`, and `route53` modules are uncommented, Terraform will create an ACM cert for `*. ` (literally), a Route53 zone for an empty string, and ALB host rules matching blank hostnames — all silently.
- Files: `envs/prod/variables.tf` (line 26)
- Current mitigation: The modules are commented out and currently produce no resources.
- Recommendations: Add a `validation` block to `variable "tenant_domain"`:
  ```hcl
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))
    error_message = "tenant_domain must be a valid apex domain, e.g. saas.example.com."
  }
  ```
  Remove the empty-string default so `terraform plan` fails fast if the value is not set in `terraform.tfvars`.

**S3 state bucket uses AES256 (SSE-S3) not SSE-KMS:**
- Risk: State files can contain sensitive values (RDS master passwords, SSM parameter values, etc.). AES256 (SSE-S3) uses AWS-managed keys with no audit trail or key rotation control. SSE-KMS provides CloudTrail logging of every state-file read.
- Files: `bootstrap/main.tf` (line 30)
- Current mitigation: Encryption is enabled; bucket is fully private (`block_public_acls = true`, etc.).
- Recommendations: Change `sse_algorithm = "AES256"` to `"aws:kms"` and add a dedicated KMS key resource in `bootstrap/main.tf`. Accept the small per-request cost for auditability.

**No IAM boundary or least-privilege policy for Terraform executor:**
- Risk: The README instructs using an "admin/bootstrap profile" for all Terraform operations. No example IAM policy or permission boundary is provided. Broad admin credentials used routinely increase blast radius on credential compromise.
- Files: `README.md`
- Current mitigation: None defined in code.
- Recommendations: Add an `iam/` directory (or a `bootstrap/iam.tf`) that creates a scoped Terraform executor role limited to the specific services used (S3, ECS, RDS, ECR, EFS, ALB, ACM, Route53, SSM, KMS). Document role assumption in the README.

**No S3 bucket policy on the state bucket:**
- Risk: The bootstrap creates the bucket with all public access blocked and SSE enabled, but no bucket policy restricts which IAM principals can read or write state. Any principal in the AWS account with `s3:GetObject` can read Terraform state (which will contain secrets once RDS and SSM modules are implemented).
- Files: `bootstrap/main.tf`
- Current mitigation: Public access is blocked; private to the account.
- Recommendations: Add `aws_s3_bucket_policy` in `bootstrap/main.tf` with a `Deny` condition for all principals except the Terraform executor role and designated admin roles.

**SSM module will store secrets — encryption tier not yet defined:**
- Risk: The SSM module's purpose includes storing RDS master credentials and HMAC salts as `SecureString` parameters. The encryption key type (default SSM key vs. CMK) is not specified in the stub.
- Files: `modules/ssm/main.tf`
- Current mitigation: Module is unimplemented; no parameters exist yet.
- Recommendations: Use a customer-managed KMS key for all `SecureString` parameters when implementing `modules/ssm/main.tf`. Provision the CMK in `bootstrap/` (or a dedicated `modules/kms/` module) so it predates the SSM parameters.

---

## Performance Bottlenecks

**No NAT gateway — tenant tasks must be on public subnets with public IPs:**
- Problem: The architecture comment in `modules/networking/main.tf` explicitly notes "NO NAT gateway (cost)" with tenant tasks on public subnets. ECS Fargate tasks on public subnets require a public IP to reach ECR, SSM, and other AWS APIs.
- Files: `modules/networking/main.tf`, `envs/prod/main.tf` (line 4)
- Cause: Cost optimization decision recorded in SEED-001.
- Impact path: Each tenant task will consume a public Elastic IP or rely on AWS-assigned public IPs. Public subnet placement increases the attack surface (tasks are directly internet-reachable on non-ALB ports unless security groups are tightly locked). The networking SG must enforce that only port 8069 from the ALB SG is permitted — any misconfiguration exposes tasks directly.
- Improvement path: Accept the trade-off at MVP; document the SG rule requirement explicitly in `modules/networking/main.tf` as a `precondition` or comment. Re-evaluate NAT gateway at ~20+ tenants when its cost is amortized.

**EFS small-file latency under `/sessions`:**
- Problem: The `modules/efs/main.tf` stub comment warns about small-file latency under `/sessions`.
- Files: `modules/efs/main.tf`
- Cause: EFS General Purpose mode has ~1-3ms per-operation latency; Odoo session files are small and numerous.
- Improvement path: When implementing `modules/efs/`, set `performance_mode = "generalPurpose"` and `throughput_mode = "elastic"`. Consider an EFS access point per tenant with a root directory to isolate I/O. Evaluate moving Odoo session storage to Redis/Elasticache if latency becomes a bottleneck.

**RDS connection exhaustion before RDS Proxy is active:**
- Problem: The SEED-001 note in `modules/rds-proxy/main.tf` states the proxy should be activated at ~30 active tenants. Until then, each Odoo worker process holds open PostgreSQL connections directly to the RDS instance.
- Files: `modules/rds-proxy/main.tf`, `modules/rds-tenant/main.tf`
- Improvement path: Size the RDS instance class based on `max_connections` headroom (as noted in the stub comment). Implement the proxy module early — before the 30-tenant threshold — to avoid an emergency migration under load.

---

## Fragile Areas

**Bootstrap local state — single point of failure:**
- Files: `bootstrap/terraform.tfstate` (absent from repo), `bootstrap/main.tf`
- Why fragile: The S3 bucket that holds all other environment state is itself managed by local Terraform state. If this file is lost (laptop failure, accidental delete) and no backup exists, Terraform loses track of the bucket, and `terraform apply` would attempt to create a duplicate or fail on the globally-unique name conflict.
- Safe modification: Always commit `bootstrap/terraform.tfstate` after any bootstrap apply. Consider migrating the bootstrap state into the bucket it created (remote state self-hosting) once the bucket exists, using `terraform init -migrate-state`.
- Test coverage: None.

**`envs/prod/backend.tf` region is hardcoded independently of `var.region`:**
- Files: `envs/prod/backend.tf` (line 12), `envs/prod/variables.tf` (line 1)
- Why fragile: If `var.region` is changed in `terraform.tfvars` (e.g., to migrate to a different region), `backend.tf` must be manually updated too. A mismatch causes Terraform to look for the state file in the wrong region.
- Safe modification: Treat `backend.tf` as a static file that must be edited in sync with any region change. Add a comment to this effect in both files.

**`rds-tenant` referenced as `module.rds_tenant` but module label uses underscore not hyphen:**
- Files: `envs/prod/main.tf` (lines 33, 35)
- Why fragile: Terraform module labels normalize hyphens to underscores in `module.<label>.*` references, so `module "rds_tenant"` must be referenced as `module.rds_tenant`. If the commented block is uncommented and a developer writes `module "rds-tenant"` (matching the directory name convention), the output reference `module.rds_tenant.endpoint` will silently break.
- Safe modification: Use `rds_tenant` (underscore) as the label consistently when uncommenting, matching the existing reference in `outputs.tf`.

---

## Scaling Limits

**Single-AZ tenant RDS at MVP:**
- Current capacity: Intended as Single-AZ (per SEED-001 note and stub comment).
- Limit: A single AZ outage (or RDS maintenance window) takes down all tenant databases simultaneously.
- Scaling path: The stub comment notes this is intentional for MVP cost. Promote to Multi-AZ by changing `multi_az = true` in the RDS instance resource when the first paying customers are onboarded. Budget ~2x RDS cost.

**No multi-region or DR plan:**
- Current capacity: All resources target `eu-central-1` (hardcoded in `envs/prod/backend.tf` and defaulted in `envs/prod/variables.tf`).
- Limit: A full region outage takes down the entire platform.
- Scaling path: Not in scope for MVP. Document as a future concern. Adding `envs/prod-dr/` pointing to a second region is the natural path.

---

## Dependencies at Risk

**AWS provider pinned at `~> 6.0` (very new major version):**
- Risk: The AWS provider v6.x is a major version that introduced breaking changes from v5.x. With a `~> 6.0` constraint (allows 6.x but not 7.x), any 6.x minor release could introduce behavioral changes before modules are implemented. No lock file is committed to pin the exact version.
- Files: `envs/prod/versions.tf`, `bootstrap/versions.tf`
- Impact: `terraform init` on a new machine may pull a newer 6.x release with changed defaults.
- Migration plan: Commit `.terraform.lock.hcl` for both configs after running `terraform init`. This pins the exact provider version without changing the constraint.

**Terraform `>= 1.11.0` lower bound only — no upper bound:**
- Risk: `required_version = ">= 1.11.0"` permits any future Terraform version including major versions (2.x, 3.x) that may have breaking HCL syntax or backend changes.
- Files: `envs/prod/versions.tf`, `bootstrap/versions.tf`
- Migration plan: Tighten to `~> 1.11` (or `>= 1.11, < 2.0`) once the project is stable to prevent accidental major-version upgrades in CI.

---

## Missing Critical Features

**No CI/CD pipeline defined:**
- Problem: No `.github/`, `.gitlab-ci.yml`, or other CI configuration exists. All `terraform plan` and `terraform apply` operations are manual via `make`.
- Blocks: Automated drift detection, plan-on-PR review, gated apply on merge.
- Recommendation: Add a GitHub Actions workflow with: `terraform fmt -check`, `terraform validate`, `terraform plan` (on PR), and `terraform apply` (on merge to main, with approval gate).

**No automated `terraform fmt` enforcement:**
- Problem: The Makefile provides `make fmt` but there is no pre-commit hook or CI check to enforce formatting. Unformatted `.tf` files are accepted silently.
- Files: `Makefile`
- Recommendation: Add a `terraform fmt -check -recursive` step to CI, or add a `.pre-commit-config.yaml` with the `terraform_fmt` hook.

**No `tfsec`, `checkov`, or similar static security analysis:**
- Problem: No security scanning tool is configured for the Terraform code. Once modules are implemented, misconfigurations (open SGs, unencrypted volumes, public RDS) will not be caught automatically.
- Recommendation: Add `tfsec` or `checkov` as a CI step. Both support Terraform natively and can be configured to fail on HIGH/CRITICAL findings.

**No `terraform validate` in CI:**
- Problem: `make validate` exists but is not enforced automatically. A developer could add a syntactically invalid stub and it would only be caught on manual `make validate`.
- Files: `Makefile`
- Recommendation: Add `terraform validate` to CI on every push.

**Only `prod` environment — no non-production baseline:**
- Problem: There is no `staging` or `dev` environment. First implementation of each module will be applied directly to production.
- Blocks: Safe iterative module development; cost-reduced testing.
- Recommendation: Create `envs/staging/` as a copy of `envs/prod/` with a distinct backend key and smaller instance types in a `staging.tfvars`.

---

## Test Coverage Gaps

**No Terraform testing (Terratest, `terraform test`, etc.):**
- What's not tested: Module input/output contract, resource creation behavior, security group rules, IAM policies.
- Files: All `modules/*/` — no `*.tftest.hcl` or test Go files exist.
- Risk: Modules can be implemented with incorrect resource arguments, wrong CIDR blocks, or missing outputs and only fail at `terraform apply` time against a real AWS account.
- Priority: Medium — acceptable at scaffold stage, but should be added before each module is considered production-ready.

**No `terraform plan` output baseline committed:**
- What's not tested: There is no recorded expected plan output to diff against. Changes to stub comments or variable defaults could silently alter plan behavior.
- Priority: Low at current stub stage; High once modules produce real resources.

---

*Concerns audit: 2026-06-19*
