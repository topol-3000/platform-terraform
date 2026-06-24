# Phase 4: Shared filesystem - Context

**Gathered:** 2026-06-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `modules/efs` and wire it into `envs/prod`, keeping the offline `make plan-check` gate green. The module provides a **shared, encrypted EFS filesystem** for the Odoo fleet (mounted at `/var/lib/odoo` per task by the provisioner adapter — durable session/filestore data across task replacement and cross-AZ reschedule).

Locked by ROADMAP Phase 4 success criteria (not gray areas — do NOT re-discuss):
- One encrypted `aws_efs_file_system` with `performance_mode = "generalPurpose"` and `throughput_mode = "elastic"`, at-rest encryption enabled.
- An EFS security group whose **only** inbound rule allows port **2049 (NFS) from the task security group id** — no CIDR-based ingress (mirrors the Phase 1/3 SG-reference pattern).
- Mount targets covering every baseline AZ, derived from `module.networking.private_subnet_ids`.
- **No per-tenant access points** are created by Terraform — the provisioner `AwsDeploymentAdapter` creates those at provision time.
- Uncomment `module "efs"` in `envs/prod/main.tf` and the `efs_id` output in `envs/prod/outputs.tf` (resolves to `module.efs.efs_id`).
- Verification is **code-complete only**: `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` via the offline `make plan-check` gate. **No `terraform apply`, no AWS spend.**

Covers requirements EFS-01, EFS-02. Per-tenant resources (access points, mounts) are explicitly out of scope — adapter-owned at runtime.

</domain>

<decisions>
## Implementation Decisions

### IA lifecycle tiering (cost vs small-file latency)
- **D-01:** Add an EFS `lifecycle_policy` with `transition_to_ia = "AFTER_30_DAYS"` **and** `transition_to_primary_storage_class = "AFTER_1_ACCESS"`. Cold files cheapen automatically (serves the locked cost-stripping theme), but any read pulls a file back to Standard, so hot Odoo session/asset files never pay the IA first-byte latency penalty — this is the explicit mitigation for the SEED-001 "watch small-file latency under /sessions" warning. Rejected: no tiering (leaves easy savings on the table) and aggressive IA-after-7d-no-return (cold reads keep paying IA latency).

### Automatic backups (durability vs MVP cost)
- **D-02:** **Do NOT** create an `aws_efs_backup_policy` this phase. Backups stay OFF for the MVP, consistent with the established cost-lean pattern (RDS proxy-off, CMK-deferred). EFS holds durable filestore/attachments, so this is flagged as a **near-term hardening item** (see Deferred Ideas), not a permanent stance. Zero extra cost and zero extra resources in the plan today. (User chose plain "off + deferred" over a feature-flagged `enable_efs_backup` toggle — keep the module lean; add the flag when backups are actually prioritized.)

### Encryption key (KMS)
- **D-03:** Carry forward Phase 3 **D-09**: set `encrypted = true` on the filesystem using the **default AWS-managed key** (`aws/elasticfilesystem`). Cheapest, zero extra resources, fully offline, consistent with RDS/SSM this milestone. A customer-managed CMK remains **deferred** to the security-hardening pass.

### Mount-target AZ safety
- **D-04:** Build mount targets keyed by **AZ**, not raw subnet, so the one-mount-target-per-AZ EFS rule can never produce a duplicate-MT apply failure that the offline `plan-check` gate would not catch. Concretely: derive a one-subnet-per-AZ map from the passed-in subnets (e.g. group by AZ and pick one subnet per AZ) and `for_each` mount targets over that map. Phase 1's layout is one public subnet per AZ today, so this is defensive insurance against future subnet-layout changes — it still produces a mount target per AZ, satisfying criteria #2. To resolve each subnet's AZ offline without a live data source, prefer passing AZ↔subnet mapping in as a variable from the networking module's known outputs (see Claude's Discretion) rather than a `data "aws_subnet"` lookup that would break the offline plan.

### Wiring & verification (carried forward from Phases 1–3)
- **D-05:** Pass `name_prefix`, the subnet set (from `module.networking.private_subnet_ids`), and `task_security_group_id` into `module "efs"`. Use the **underscore** module label (`module.efs`). All resource names carry `var.name_prefix`; all wiring stays in `envs/prod/main.tf` (no module-to-module calls). **Pre-declare every new module variable before uncommenting the call** (CONCERNS.md) — an undeclared argument fails `terraform plan` with "unsupported argument".
- **D-06:** Keep the plan **fully offline** — no `data "aws_subnet"` / AZ-lookup data sources, no STS/account-id reads, no `skip_*` provider flags. The plan must stay green via the existing dummy-AWS env gate. The EFS SG ingress uses `security_groups = [var.task_security_group_id]` (SG reference), never a CIDR.

### Claude's Discretion
- **AZ↔subnet mapping mechanism for D-04** — the cleanest offline approach is for the networking module to expose subnet→AZ info (e.g. a `private_subnet_az_map` / `private_subnets_by_az` output) that `envs/prod` passes into the efs module; if such an output doesn't exist yet, the planner may add it to `modules/networking/outputs.tf` (and a corresponding `efs` input variable) OR `for_each` directly over `private_subnet_ids` with a comment noting the one-subnet-per-AZ invariant from Phase 1. Planner's discretion — the hard requirement is "one mount target per AZ, no offline-plan-invisible apply failure."
- **`aws_efs_mount_target` vs `for_each` style, resource/label naming, SG resource structure, `creation_token`** — planner's discretion following established conventions (`"${var.name_prefix}-efs"` etc.).
- **Whether to also export `efs_arn`/`efs_dns_name`** — only `efs_id` is contractually required (EFS-02). Add others only if cheap and useful; don't expand the provisioner contract gratuitously.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & project scope
- `.planning/REQUIREMENTS.md` — EFS-01 (encrypted EFS, mount target per AZ, SG 2049-from-task-SG-only, no TF access points), EFS-02 (`efs_id` exported + wired).
- `.planning/ROADMAP.md` §"Phase 4: Shared filesystem" — goal + 4 success criteria (the locked EFS shape).
- `.planning/PROJECT.md` — core value, constraints (no NAT, `name_prefix`, SSM-over-Secrets-Manager, code-complete verification, cost-stripping theme), EFS mount-path note (`/var/lib/odoo`, access points adapter-owned).

### Prior-phase decisions to honor
- `.planning/phases/03-databases-and-secrets/03-CONTEXT.md` — **D-09** (AWS-managed KMS keys, CMK deferred — carried forward here as D-03); offline-plan discipline (no live data sources, no `skip_*` flags); cost-lean MVP pattern (proxy-off as the template for backups-off); pre-declare module variables before uncommenting; underscore module labels.
- `.planning/phases/01-networking-module/01-CONTEXT.md` — offline plan via dummy-AWS env, `name_prefix` + default-tags patterns, the **SG-reference ingress pattern** (port-from-SG, not CIDR) that the EFS SG must mirror; one-public-subnet-per-AZ layout (the invariant behind D-04).

### Existing architecture & conventions (codebase maps)
- `.planning/codebase/ARCHITECTURE.md` — root-module composition, `name_prefix`, anti-patterns (no module-to-module calls, no hardcoded names), provisioner output contract.
- `.planning/codebase/CONVENTIONS.md` — module interface / variable / output naming.
- `.planning/codebase/CONCERNS.md` — pre-declare module variables before uncommenting calls; underscore module labels; offline-plan constraints.

### Files to implement / edit
- `modules/efs/{main,variables,outputs}.tf` — currently stubs. Add: `aws_efs_file_system` (encrypted, generalPurpose, elastic, lifecycle_policy per D-01), `aws_efs_mount_target` (per-AZ, D-04), `aws_security_group` (2049 from task SG), `efs_id` output. Add `subnet_ids`/AZ-mapping and `task_security_group_id` (and `vpc_id` if the SG needs it) variables.
- `envs/prod/main.tf` — uncomment + wire `module "efs"` (build step 7) with underscore label; pass `name_prefix`, subnets, `task_security_group_id`.
- `envs/prod/outputs.tf` — uncomment `efs_id` (lines ~51–53) → `module.efs.efs_id`.
- `modules/networking/outputs.tf` — *possibly* add an AZ↔subnet output if the planner takes that route for D-04.

### External (architecture source of truth, may be outside this repo)
- `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md` — EFS mounted at `/var/lib/odoo`, durable across task replacement/cross-AZ reschedule (NOT EBS); "watch small-file latency under /sessions" (the driver behind the D-01 return-on-access choice); per-tenant access points created by the adapter, not Terraform.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `local.name_prefix = "${var.project}-${var.environment}"` (= `odoo-saas-prod`) in `envs/prod/main.tf` — pass as the efs module's `name_prefix`.
- `default_tags` in `envs/prod/providers.tf` — resources inherit Project/Environment/ManagedBy/Repo tags; the module adds only `Name` tags.
- **The networking/RDS SG pattern is the direct template for the EFS SG** — `ingress { security_groups = [<task sg id>] }` with `from_port/to_port = 2049`, NOT a CIDR. Phases 1 and 3 both use this exact shape.
- `module.networking.private_subnet_ids` (one public subnet per AZ across ≥2 AZs) feeds the mount targets. `module.networking.task_security_group_id` feeds the EFS SG ingress.
- Commented stub blocks already define the expected interface: `module "efs"` in `envs/prod/main.tf` (lines ~84+) and the `efs_id` output in `envs/prod/outputs.tf` (lines ~51–53).
- Phases 1–3 implemented and wired; the offline `make plan-check` gate already works — Phase 4 must keep it green and grow the resource count.

### Established Patterns
- Modules receive inputs via variables, expose typed outputs consumed only by the root config (no cross-module references).
- Resource names `"${var.name_prefix}-<thing>"`; never hardcoded. Module labels referenced with underscores (`module.efs.*`).
- `make fmt` / `make validate` wrap `terraform fmt -recursive` / `validate`; **`make plan-check`** is the offline gate (memory: use `make plan-check`, not `make plan`).
- Variables get prod-sensible defaults so the plan runs with zero tfvars editing; required-but-empty values get a `# TODO: set in terraform.tfvars` marker.

### Integration Points
- `module.efs.efs_id` → `envs/prod/outputs.tf` `efs_id` → provisioner `aws_efs_id` (the adapter creates per-tenant access points against this filesystem id at provision time).
- No new provider dependency expected — `hashicorp/aws ~> 6.0` covers all EFS resources.

</code_context>

<specifics>
## Specific Ideas

- The SEED-001 "/sessions small-file latency" warning is the specific driver behind D-01's `transition_to_primary_storage_class = AFTER_1_ACCESS` — the user wants IA cost savings WITHOUT punishing hot session/asset reads.
- The user continues the consistent posture from Phase 3: cost-lean MVP defaults (IA tiering on, backups off, AWS-managed keys) with a robustness floor that doesn't cost money (the per-AZ mount-target dedup guard, D-04).
- Backups-off is explicitly framed as "deferred, not rejected" — EFS durability hardening is expected to come back as a near-term item.

</specifics>

<deferred>
## Deferred Ideas

- **EFS automatic backups** (`aws_efs_backup_policy` / AWS Backup) — deferred from this phase (D-02). Flagged as a **near-term hardening item** because EFS holds durable filestore/attachments; revisit once the MVP plan is green, likely alongside the broader security/durability hardening pass.
- **Customer-managed KMS CMK for EFS at-rest encryption** (audit + rotation) — deferred with the rest of the CMK work (D-03 / Phase 3 D-09); MVP uses the AWS-managed key.
- **Provisioned-throughput floor / non-elastic throughput tuning** — out of scope; `throughput_mode = elastic` is locked by criteria.
- **Per-tenant EFS access points** — explicitly NOT Terraform's job; owned by the provisioner `AwsDeploymentAdapter` at runtime.

### Reviewed Todos (not folded)
None — no pending todos matched this phase.

</deferred>

---

*Phase: 4-shared-filesystem*
*Context gathered: 2026-06-24*
