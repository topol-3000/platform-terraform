# Phase 3: Databases and secrets - Context

**Gathered:** 2026-06-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement four modules and wire them into `envs/prod`, keeping the offline `make plan-check` gate green:

- `modules/ssm` — Parameter Store **SecureString** parameters for the HMAC salt, RDS master credentials, and tokens. No secret values in plaintext outputs or state-as-plaintext; only parameter names/ARNs are exported.
- `modules/rds-tenant` — shared **Single-AZ** (`multi_az = false`) PostgreSQL instance (database-per-tenant model), a DB subnet group over the baseline subnets, and an RDS SG accepting 5432 **only** from the task SG id (and the proxy SG when the proxy is active).
- `modules/rds-proxy` — RDS Proxy fronting the tenant RDS; **present and wired but feature-flagged OFF** for future activation at ~30 tenants.
- `modules/rds-control-plane` — a **separate Multi-AZ** (`multi_az = true`) PostgreSQL instance for provisioner control-plane data only; no resources shared with the tenant instance.

Covers requirements RDS-01, RDS-02, RDS-03, RDS-04, SSM-01, SSM-02, and VER-01 (cross-cutting). Verification is **code-complete only** — `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` via the offline `make plan-check` gate. **No `terraform apply`, no AWS spend.**

Per-tenant resources (per-tenant databases/roles, ECS services, target groups, DNS records) are NOT created here — the provisioner `AwsDeploymentAdapter` owns those at runtime.

</domain>

<decisions>
## Implementation Decisions

### Secret values & RDS master-password flow
- **D-01:** Use the **`hashicorp/random` provider `random_password`** to generate RDS master passwords at plan time. The generated value is written to an `aws_ssm_parameter` **SecureString** AND passed to `aws_db_instance.password` — single source of truth, fully offline (no live calls), never hardcoded. The secret value lives only in encrypted S3 state + the SSM SecureString. The HMAC salt is generated the same way (`random_password`/`random_id`).
- **D-02:** Add `lifecycle { ignore_changes = [password] }` on each `aws_db_instance` so out-of-band password rotation does not cause Terraform drift. Apply the equivalent (`ignore_changes = [value]`) on the SSM parameter if the value is expected to be rotated externally.
- **D-03:** Do **NOT** read SSM via a `data "aws_ssm_parameter"` source — that requires the parameter to pre-exist (a live call) and would break the offline `make plan-check` gate. The SSM parameter and the RDS instance are created in the same config from the same `random_password`. Rejected alternatives: tfvars-provided secret values (breaks the zero-edit plan + worse secret hygiene on disk) and dummy-value-plus-`ignore_changes`-injected-out-of-band (more moving parts, RDS still needs a real password).

### RDS Proxy — feature-flagged, default OFF
- **D-04:** Implement the **full** proxy (`aws_db_proxy` + `aws_db_proxy_default_target_group` + `aws_db_proxy_target` + IAM role for secret access + the Secrets Manager secret the proxy auth block requires) but gate **every** proxy resource behind `var.enable_rds_proxy` (**default `false`**) using `count = var.enable_rds_proxy ? 1 : 0`. Code is present and wired for one-flag activation at ~30 tenants; **0 proxy resources in the plan today**.
- **D-05:** This deliberately keeps the **SSM-only constraint intact** at MVP: the Secrets Manager secret the RDS Proxy mandates (proxy auth cannot use SSM) only materializes when the flag is flipped. RDS Proxy is the single sanctioned exception, and only at activation time.
- **D-06 (criteria reinterpretation — flag for planner/verifier):** Because the proxy is flag-gated OFF, ROADMAP Phase 3 success criteria #3 ("declares an RDS Proxy … present and wired") and #6 ("the proxy appearing in the plan") are satisfied as **"declared, fully implemented, and wired behind `enable_rds_proxy`"** — the proxy will NOT appear in the default plan. The proxy module's outputs (`endpoint`) must still resolve (guard with `try()`/conditional or `length()` indexing) so `envs/prod` wiring stays valid with the flag off.

### RDS instance defaults & safety
- **D-07:** Sizing (cost-stripping theme; all overridable via tfvars): tenant RDS and control-plane RDS both default to **`db.t4g.small`** (Graviton burstable), **gp3** storage ~20GB with **storage autoscaling** (`max_allocated_storage`). Per SEED-001, size on `max_connections` (~5–20 conns/tenant), not raw DB count. `db.t4g.micro` is an acceptable fallback if even cheaper is wanted.
- **D-08:** Safety on **both** instances: **`deletion_protection = true`** and **`skip_final_snapshot = false`** (a final snapshot is taken on deletion; set a `final_snapshot_identifier`). Mirrors the bootstrap S3 `prevent_destroy` ethos. (User chose this over both unprotected teardown and the extra control-plane `prevent_destroy` lifecycle — standard protection on both is sufficient.)

### Encryption keys (KMS)
- **D-09:** **AWS-managed keys** this phase: SSM SecureStrings use the default `alias/aws/ssm`; RDS instances set `storage_encrypted = true` with the default AWS-managed RDS key. Encryption is ON everywhere — just not customer-managed. Zero extra resources, fully offline, cheapest. A customer-managed CMK (CloudTrail audit + rotation, per CONCERNS.md) is **deferred** to a later security-hardening pass.

### Wiring & verification (carried forward from Phases 1–2)
- **D-10:** Uncomment the `module "rds_tenant"`, `module "rds_proxy"`, and `module "rds_control_plane"` calls (build step 5) and the `module "ssm"` call (build step 6) in `envs/prod/main.tf`, using **underscore** module labels. Uncomment the `tenant_rds_endpoint`, `rds_proxy_endpoint`, and a control-plane endpoint output in `envs/prod/outputs.tf`. SSM exports **only** non-secret references (param names/ARNs), never values. All resource names carry `var.name_prefix`; all wiring stays in `envs/prod/main.tf` (no module-to-module calls).
- **D-11:** **Pre-declare all module variables before uncommenting calls** (CONCERNS.md): add `subnet_ids` (and `vpc_id` if needed) to `modules/rds-tenant/variables.tf`, plus the new inputs each module needs (`task_security_group_id` for the RDS SG ingress, `enable_rds_proxy`, etc.). An undeclared argument fails `terraform plan` with "unsupported argument".
- **D-12:** Verification is the offline `make plan-check` gate (dummy AWS env from Phase 1 D-06). All chosen approaches (random_password, AWS-managed keys, flag-gated proxy) keep the plan fully offline — no live-call data sources, no `skip_*` provider flags.

### Claude's Discretion
- **Postgres major version** — default to a current stable major (e.g. 16); planner's discretion. Set `engine_version` explicitly and pin a parameter-group family.
- **Control-plane RDS SG ingress source** — the provisioner connects to the control-plane DB; default the control-plane SG to accept 5432 from the task SG id (provisioner runs in-cluster), mirroring the tenant RDS SG pattern. Planner may refine if a dedicated provisioner SG is preferred.
- **SSM parameter naming/paths** — e.g. `/${name_prefix}/rds/tenant/master-password`, `/.../rds/control-plane/master-password`, `/.../hmac-salt`. Planner's discretion following `name_prefix` convention.
- **What "tokens" SecureStrings to scaffold** — RDS-02/SSM-01 mention "tokens" loosely; scaffold the HMAC salt + both RDS master credential params as the concrete set, and add a clearly-named placeholder/structure for tokens if a specific token is known. Don't invent secrets with no consumer.
- **`count`/`for_each` vs single-resource style, resource ordering, parameter-group and subnet-group structure** — planner's discretion following established conventions.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & project scope
- `.planning/REQUIREMENTS.md` — RDS-01..04, SSM-01/02, VER-01; out-of-scope boundaries (per-tenant resources are adapter-owned).
- `.planning/ROADMAP.md` §"Phase 3: Databases and secrets" — goal + 6 success criteria. **Note D-06:** criteria #3/#6 are reinterpreted for the flag-gated proxy (declared & wired behind `enable_rds_proxy`, not present in the default plan).
- `.planning/PROJECT.md` — core value, constraints (SSM-over-Secrets-Manager, no NAT, `name_prefix`, code-complete verification, cost-stripping), tenant/control-plane DB isolation.

### Prior-phase decisions to honor
- `.planning/phases/01-networking-module/01-CONTEXT.md` — offline plan via dummy AWS env (D-06), no `skip_*` provider flags (D-07), `name_prefix` + default-tags patterns, prod-sensible defaults so the plan runs with zero tfvars editing. The networking SG-reference ingress pattern (5432-from-SG, not CIDR) is the template for the RDS SG.
- `.planning/phases/02-container-platform/02-CONTEXT.md` — managed-resource-over-external-dependency reasoning; offline-plan discipline (no STS/account-id data sources); modules expose typed outputs consumed only by the root.

### Existing architecture & conventions (codebase maps)
- `.planning/codebase/ARCHITECTURE.md` — root-module composition, `name_prefix`, anti-patterns (no module-to-module calls, no hardcoded names, no plaintext secrets), provisioner output contract.
- `.planning/codebase/CONVENTIONS.md` — module interface / variable / output naming.
- `.planning/codebase/CONCERNS.md` — **pre-declare module variables before uncommenting calls** (rds-tenant `subnet_ids`/`vpc_id`); underscore module labels; SSM CMK recommendation (deferred per D-09); RDS storage-encryption note; tenant/control-plane isolation.

### Files to implement / edit
- `modules/rds-tenant/{main,variables,outputs}.tf` — Single-AZ instance, subnet group, SG (5432 from task SG), endpoint output. Currently stubs.
- `modules/rds-proxy/{main,variables,outputs}.tf` — flag-gated proxy + target group + IAM role + Secrets Manager secret; conditional `endpoint` output. Currently stubs.
- `modules/rds-control-plane/{main,variables,outputs}.tf` — separate Multi-AZ instance, own subnet group + SG, endpoint output. Currently stubs.
- `modules/ssm/{main,variables,outputs}.tf` — SecureString params (random_password sourced), outputs param names/ARNs only. Currently stubs.
- `envs/prod/main.tf` — uncomment + wire `rds_tenant`/`rds_proxy`/`rds_control_plane` (step 5) and `ssm` (step 6) with underscore labels; pass `subnet_ids`, `task_security_group_id`, `enable_rds_proxy`.
- `envs/prod/outputs.tf` — uncomment `tenant_rds_endpoint`, `rds_proxy_endpoint`, and add a control-plane endpoint output.
- `envs/prod/variables.tf` — add `enable_rds_proxy` (default false) and any sizing/version vars exposed for tfvars override.
- `envs/prod/versions.tf` — add `hashicorp/random` to `required_providers` (new dependency from D-01).

### External (architecture source of truth, may be outside this repo)
- `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md` — locked target architecture: shared RDS (DB-per-tenant) sized on max_connections, separate Multi-AZ control-plane DB, RDS Proxy at ~30 tenants, SSM Parameter Store over Secrets Manager. Treat README §Roadmap + ARCHITECTURE.md as the in-repo proxy if SEED-001 is unavailable.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `local.name_prefix = "${var.project}-${var.environment}"` (= `odoo-saas-prod`) in `envs/prod/main.tf` — pass as each module's `name_prefix`.
- `default_tags` in `envs/prod/providers.tf` (Project/Environment/ManagedBy/Repo) — resources inherit tags; modules add only `Name` tags.
- **The networking SG pattern is the direct template for the RDS SG** — `modules/networking/main.tf` `aws_security_group.task` uses `ingress { security_groups = [<sg id>] }` (SG reference, NOT a CIDR). The RDS SG mirrors this with `from_port/to_port = 5432` sourcing the task SG id passed in as a variable.
- `module.networking.private_subnet_ids` (≥2 public subnets across AZs) feeds the RDS DB subnet group(s). `module.networking.task_security_group_id` feeds the RDS SG ingress.
- Commented stub blocks already define the expected interface: `module "rds_tenant"` (takes `subnet_ids`), `module "rds_proxy"`, `module "rds_control_plane"`, `module "ssm"` in `envs/prod/main.tf`; `tenant_rds_endpoint` / `rds_proxy_endpoint` in `envs/prod/outputs.tf`.
- Phases 1–2 implemented and wired (13 resources); the offline `make plan-check` gate already works — Phase 3 must keep it green and grow the resource count.

### Established Patterns
- Modules receive inputs via variables, expose typed outputs consumed only by the root config (no cross-module references).
- Resource names `"${var.name_prefix}-<thing>"`; never hardcoded. Module labels referenced with underscores (`module.rds_tenant.*`).
- `make fmt` / `make validate` wrap `terraform fmt -recursive` / `validate`; `make plan-check` is the offline gate (note the memory: use `make plan-check`, not `make plan`).
- Variables get prod-sensible defaults so the plan runs with zero tfvars editing (Phase 1 pattern); required-but-empty values get a `# TODO: set in terraform.tfvars` marker.

### Integration Points
- `module.rds_tenant.endpoint` → `envs/prod/outputs.tf` `tenant_rds_endpoint` → provisioner `aws_shared_rds_endpoint`.
- `module.rds_proxy.endpoint` → `envs/prod/outputs.tf` `rds_proxy_endpoint` → provisioner `aws_rds_proxy_endpoint` (resolves to null/empty when flag off — guard the output).
- `module.rds_control_plane.endpoint` → new control-plane endpoint output (control-plane consumed by the provisioner platform DB connection, separate from tenant).
- New provider dependency: `hashicorp/random` (D-01) must be added to `envs/prod/versions.tf` `required_providers`.

</code_context>

<specifics>
## Specific Ideas

- The offline-plan discipline is the hard constraint that shaped every choice: no `data "aws_ssm_parameter"` reads, no STS/account-id lookups — secrets are generated by `random_password` so the plan needs zero live calls.
- The user consistently favors the cost-lean MVP path (burstable t4g, AWS-managed keys, proxy off) while keeping data safety non-negotiable (deletion_protection + final snapshot on both DBs).
- Tenant vs control-plane isolation is architectural, not optional: two separate `aws_db_instance` resources, separate subnet groups, separate SGs — nothing shared.

</specifics>

<deferred>
## Deferred Ideas

- **Customer-managed KMS CMK** for SSM SecureStrings and RDS storage (CloudTrail audit + key rotation, per CONCERNS.md) — deferred to a security-hardening pass. D-09 uses AWS-managed keys for the MVP.
- **RDS Proxy activation** (`enable_rds_proxy = true`) — flip the flag at ~30 active tenants; validate Odoo bus LISTEN/NOTIFY through the proxy (connection-pinning risk per SEED-001) before relying on it. Materializes the Secrets Manager secret + IAM role at that point.
- **Control-plane prevent_destroy lifecycle / max protection** — considered (option B in RDS safety) but not adopted; standard deletion_protection on both is sufficient for now. Revisit if control-plane SLA hardening is prioritized.
- **`db.t4g.micro` / further downsizing** and **non-burstable m-class upsizing** — both available as tfvars overrides; `db.t4g.small` is the default middle ground.
- **Read replicas, PgBouncer-style pooling beyond RDS Proxy, cross-region DR** — out of MVP scope.

### Reviewed Todos (not folded)
None — no pending todos matched this phase.

</deferred>

---

*Phase: 3-databases-and-secrets*
*Context gathered: 2026-06-23*
