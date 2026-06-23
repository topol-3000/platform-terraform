# Phase 2: Container platform - Context

**Gathered:** 2026-06-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `modules/ecr` (a managed ECR repository for the `odoo-core` image) and `modules/ecs` (a shared ECS/Fargate cluster), then wire both into `envs/prod` so `make plan-check` stays green with the new resources in the plan. Export the two contract outputs: `ecr_image_uri` (= the ECR repository URL) and `ecs_cluster_arn`. Verification is **code-complete only** — `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` via the offline `make plan-check` gate. No `terraform apply`, no AWS spend.

Covers requirements ECR-01, ECR-02, ECS-01, ECS-02, and VER-01 (see REQUIREMENTS.md). Per-tenant resources (task definitions, ECS services, image builds/pushes) are NOT created here — the provisioner adapter and CI/CD own those.
</domain>

<decisions>
## Implementation Decisions

### ECR — managed repository (not pull-through cache)
- **D-01:** `modules/ecr` declares a **managed `aws_ecr_repository`** for the `odoo-core` image — **NOT** a GHCR pull-through cache. This **changes requirement ECR-01** (and the SEED-001 pull-through rationale). Drivers: (1) the team is moving to AWS-native image storage and will make source repos private; (2) a managed repo needs **no upstream GHCR credential** (a pull-through cache from `ghcr.io` mandates a GitHub PAT in Secrets Manager — a forced exception to the SSM-only rule — and it becomes mandatory once the repo goes private); (3) a managed repo exposes `repository_url` as a **resource attribute**, so `image_uri` resolves with no account-id variable and no `aws_caller_identity` STS call — keeping the offline `make plan-check` gate intact (preserves Phase 1 D-06/D-07). REQUIREMENTS.md and ROADMAP.md have been updated to match.
- **D-02:** `image_uri` output = `aws_ecr_repository.<label>.repository_url` (no hand-built `<acct>.dkr.ecr...` string, no tag pinned in the output — the provisioner/adapter appends the tag it deploys). This is the "best practice" resolution to the original account-id-in-URI question: derive the URI from the resource attribute.
- **D-03:** No Secrets Manager secret, no `credential_arn`, no `account_id` variable are introduced this phase — all were only needed by the rejected pull-through-cache path.

### ECS — cluster + Fargate capacity providers
- **D-04:** `modules/ecs` declares `aws_ecs_cluster` **plus** an `aws_ecs_cluster_capacity_providers` association wiring **`FARGATE` + `FARGATE_SPOT`**, and enables **Container Insights**. (Chosen over a bare cluster — closer to production-ready; the provisioner sets only per-tenant services/tasks at runtime, so the cluster + capacity providers belong in the baseline.)
- **D-05:** `ecs` exports `cluster_arn`; the cluster is `name_prefix`-named.

### Wiring & verification (carried forward from Phase 1)
- **D-06:** Uncomment the `module "ecr"` and `module "ecs"` calls in `envs/prod/main.tf` (build order: ECR step 3, ECS step 4) and the `ecr_image_uri` / `ecs_cluster_arn` outputs in `envs/prod/outputs.tf`. Each resource name carries `var.name_prefix`; all wiring stays in `envs/prod/main.tf` (modules call no other modules).
- **D-07:** Verification is the offline `make plan-check` gate (dummy AWS env from Phase 1 D-06). The managed-repo + cluster choices keep the plan fully offline (no live-call data sources). Provider config stays clean — no `skip_*` flags added (Phase 1 D-07).

### Claude's Discretion
- ECR repo naming / label and the exact repository name under `name_prefix` (planner's discretion per the user — follow `name_prefix` conventions, e.g. `"${var.name_prefix}-odoo-core"`).
- ECR repository hardening defaults: `image_scanning_configuration { scan_on_push = true }`, `image_tag_mutability`, encryption (AES256 default vs KMS), and a lifecycle policy to expire untagged images (cost). Apply sensible best-practice defaults; these are not user-facing decisions.
- ECS cluster setting style (e.g. `setting { name = "containerInsights" ... }` value `enabled` vs `enhanced`) and whether capacity-provider defaults set a `default_capacity_provider_strategy`.
- `count`/`for_each` vs single-resource style; resource ordering.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & project scope
- `.planning/REQUIREMENTS.md` — ECR-01 (now: managed repository), ECR-02, ECS-01, ECS-02, VER-01; out-of-scope boundaries. **ECR-01 was amended 2026-06-23 per D-01 — read the current text, not the original pull-through wording.**
- `.planning/ROADMAP.md` §"Phase 2: Container platform" — goal + success criteria (criterion 1 amended to managed repository).
- `.planning/PROJECT.md` — core value, constraints (no NAT, `name_prefix`, code-complete verification, SSM-over-Secrets-Manager), key decisions.

### Prior-phase decisions to honor
- `.planning/phases/01-networking-module/01-CONTEXT.md` — D-06 (offline plan via dummy AWS env; no live-call data sources), D-07 (no `skip_*` provider flags), `name_prefix` + default-tags patterns, prod-sensible defaults so plan runs with zero tfvars editing.

### Existing architecture & conventions (codebase maps)
- `.planning/codebase/ARCHITECTURE.md` — root-module composition, `name_prefix` abstraction, anti-patterns (no module-to-module calls, no hardcoded names, no plaintext secrets), provisioner output contract.
- `.planning/codebase/CONVENTIONS.md` — module interface / variable / output naming conventions.
- `.planning/codebase/CONCERNS.md` — pre-declare expected variables before uncommenting module calls; module labels use underscores.

### Files to implement / edit
- `modules/ecr/main.tf`, `modules/ecr/outputs.tf` (and `variables.tf` if inputs beyond `name_prefix` are needed) — currently stubs.
- `modules/ecs/main.tf`, `modules/ecs/outputs.tf` (and `variables.tf` as needed) — currently stubs.
- `envs/prod/main.tf` — uncomment + wire the `module "ecr"` (step 3) and `module "ecs"` (step 4) calls.
- `envs/prod/outputs.tf` — uncomment `ecr_image_uri` (`module.ecr.image_uri`) and `ecs_cluster_arn` (`module.ecs.cluster_arn`).

### External (architecture source of truth, may be outside this repo)
- `provisioner/.planning/seeds/SEED-001-aws-real-deployment.md` — locked target architecture. **Note:** its ECR section assumes a GHCR pull-through cache; D-01 supersedes that for this repo. Treat README §Roadmap + ARCHITECTURE.md as the in-repo proxy if SEED-001 is unavailable.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `local.name_prefix = "${var.project}-${var.environment}"` (= `odoo-saas-prod`) in `envs/prod/main.tf` — pass as each module's `name_prefix`.
- `default_tags` in `envs/prod/providers.tf` (Project/Environment/ManagedBy/Repo) — resources inherit tags; modules add only Name-style tags.
- Commented `module "ecr"` / `module "ecs"` blocks (`envs/prod/main.tf` lines ~22–32) and commented `ecs_cluster_arn` / `ecr_image_uri` outputs (`envs/prod/outputs.tf`) already define the expected interface: `module.ecs.cluster_arn`, `module.ecr.image_uri`.
- Phase 1 networking is implemented and wired (9 resources) — the offline `make plan-check` gate already works; Phase 2 must keep it green and grow the resource count.

### Established Patterns
- Modules receive `name_prefix`, expose typed outputs consumed only by the root config (no cross-module references).
- Resource names `"${var.name_prefix}-<thing>"`; never hardcoded. Module labels referenced with underscores.
- `make fmt` / `make validate` wrap `terraform fmt -recursive` / `validate`; `make plan-check` is the offline gate.

### Integration Points
- `module.ecr.image_uri` → `envs/prod/outputs.tf` `ecr_image_uri` → provisioner `aws_ecr_image`.
- `module.ecs.cluster_arn` → `envs/prod/outputs.tf` `ecs_cluster_arn` → provisioner `aws_ecs_cluster`.
- ECR and ECS consume **no** networking outputs — they share only the root config and the plan gate (per ROADMAP Phase 2 "Depends on").
</code_context>

<specifics>
## Specific Ideas

- The user explicitly prefers AWS-native image storage and intends to make source repos private — the direct driver for the managed-ECR-repository choice (D-01).
- `image_uri` must derive from the repository resource attribute (`repository_url`), not a hand-assembled account-id string — keeps the plan offline and is the user's "best practices" answer.
- ECS cluster must include Fargate + Fargate-Spot capacity providers and Container Insights (D-04), not a bare cluster.
</specifics>

<deferred>
## Deferred Ideas

- **GHCR pull-through cache** — the originally-specified approach; deferred/dropped in favor of a managed repo (D-01). Re-open only if the team later wants ECR to mirror an external GHCR source of truth (would reintroduce the Secrets Manager credential requirement).
- **CI/CD build-and-push pipeline for `odoo-core`** — getting the image into the ECR repo is out of this Terraform baseline's scope (separate repo/pipeline). Terraform only provisions the empty repository.
- **ECR replication / cross-region, KMS CMK for repo encryption** — hardening beyond the MVP baseline; revisit later.
- **VPC endpoints for ECR (api/dkr) + S3** — cleaner no-NAT image-pull path for tasks on public subnets; belongs in a networking-hardening pass (already noted in Phase 1 deferred ideas).

### Reviewed Todos (not folded)
None — no pending todos matched this phase.
</deferred>

---

*Phase: 2-container-platform*
*Context gathered: 2026-06-23*
