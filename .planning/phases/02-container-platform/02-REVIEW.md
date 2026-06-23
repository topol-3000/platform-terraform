---
phase: 02-container-platform
reviewed: 2026-06-23T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - modules/ecr/main.tf
  - modules/ecr/outputs.tf
  - modules/ecs/main.tf
  - modules/ecs/outputs.tf
  - envs/prod/main.tf
  - envs/prod/outputs.tf
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-06-23
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed the container-platform phase: the new `modules/ecr` and `modules/ecs`
modules plus their wiring in `envs/prod/main.tf` and re-export in
`envs/prod/outputs.tf`. The code is well-formed (`terraform fmt -check`
passes), follows the project's `var.name_prefix` naming rule, uses only the
documented `Name` tag (no extra per-resource tag blocks), and exposes no
secrets in outputs or state. The module interface (`name_prefix` as sole
required input, all wiring in the root, no module-to-module calls) matches the
locked architecture.

No critical (BLOCKER) defects were found. Two WARNING-level issues concern a
false guarantee stated in an ECR comment and a silently un-bounded growth
condition in the tagged-image set. Three INFO items cover documentation drift
against `CLAUDE.md`.

Note on scope: cost concerns (e.g. unbounded ECR storage) are out of v1 review
scope and are NOT flagged as findings on cost grounds alone. WR-01 is flagged
because the in-code comment asserts a guarantee the code does not provide — a
correctness-of-documentation defect, not a cost critique.

## Warnings

### WR-01: ECR lifecycle policy does not bound tagged-image growth, contradicting its own comment

**File:** `modules/ecr/main.tf:33-56`
**Issue:** The comment block states the lifecycle rule prevents "registry bloat
and unbounded storage cost" and that "without this rule the registry grows
without bound." But the single rule only matches `tagStatus = "untagged"`.
Every released image is pushed with an immutable tag (`image_tag_mutability =
"IMMUTABLE"`, line 17), so tagged images are never untagged and never expire —
the tagged set grows without bound regardless of this rule. The stated guarantee
is therefore false: the most durable source of growth (immutable release tags)
is uncovered. This is a correctness mismatch between the comment's claim and the
policy's behavior, and it will surprise an operator who trusts the comment.
**Fix:** Either correct the comment to scope the guarantee to untagged layers
only, or add a second rule that caps retained tagged images. Example second
rule (keep the most recent N tagged images):
```hcl
{
  rulePriority = 2
  description  = "Keep only the 30 most recent tagged images"
  selection = {
    tagStatus     = "tagged"
    tagPatternList = ["*"]
    countType     = "imageCountMoreThan"
    countNumber   = 30
  }
  action = { type = "expire" }
}
```
Note `tagPatternList` requires `tagStatus = "tagged"`; validate the chosen
pattern against retention needs before applying. If trimming tagged images is
undesirable, instead reword the comment to claim only "expire untagged
intermediate layers."

### WR-02: ECS default capacity-provider strategy never schedules onto FARGATE_SPOT

**File:** `modules/ecs/main.tf:32-44`
**Issue:** The default strategy gives FARGATE `base = 1, weight = 1` and
FARGATE_SPOT `base = 0, weight = 1`. `base` is satisfied first (1 task to
FARGATE), then remaining tasks split by `weight` (1:1). For a single-task tenant
service — the expected shape for one Odoo task per tenant — the one task is
consumed by FARGATE's `base = 1`, so it never lands on FARGATE_SPOT. The
comment on lines 39-44 advertises FARGATE_SPOT as delivering "cost savings,"
but under the documented per-tenant single-task topology the default strategy
yields zero Spot placement. The wiring is valid Terraform and not a crash, but
the cost-optimization intent stated in the comment is not achieved for the
common case, which is a behavior/intent mismatch.
**Fix:** Decide the intended behavior explicitly. If Spot should carry default
tenant tasks, drop FARGATE's `base` to 0 and weight Spot higher, e.g.:
```hcl
default_capacity_provider_strategy {
  capacity_provider = "FARGATE_SPOT"
  weight            = 4
  base              = 0
}
default_capacity_provider_strategy {
  capacity_provider = "FARGATE"
  weight            = 1
  base              = 0
}
```
If the intent is that the provisioner always sets a per-service strategy and the
cluster default is just a safe fallback, correct the comment to say so rather
than claiming Spot cost savings happen by default.

## Info

### IN-01: ECR module diverges from the `CLAUDE.md` architecture description (pull-through cache)

**File:** `modules/ecr/main.tf:1-31`
**Issue:** `CLAUDE.md` describes `modules/ecr` as an "ECR pull-through cache for
odoo-core image sourced from GHCR" and lists it as an architectural constraint
("Only pulls from GHCR to avoid rate limits"). The implemented resource is a
plain managed `aws_ecr_repository` fed by CI/CD pushes — no pull-through cache,
no GHCR upstream. The module's own header comment explains this as decision
D-01 superseding the seed, so the code is internally justified, but the
project-level `CLAUDE.md` architecture/anti-pattern text is now stale and will
mislead future readers.
**Fix:** Update the `CLAUDE.md` component table and "ECR pull-through cache"
constraint to reflect D-01 (managed repository, CI/CD push), or add a one-line
cross-reference to D-01 there.

### IN-02: ECS and ECR modules omit `versions.tf` per the documented standard file set

**File:** `modules/ecr/` , `modules/ecs/`
**Issue:** `CLAUDE.md` Conventions state the standard file set per module is
`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. Both new modules ship
only the first three. This is consistent with the existing `modules/networking`
module (which also omits `versions.tf`), so it reflects an established de-facto
pattern rather than a regression — flagged as INFO only. Provider/version
constraints are inherited from the `envs/prod` root, so `validate`/`plan` are
unaffected.
**Fix:** Either add minimal `versions.tf` stubs to the new modules for
consistency with the documented standard, or update `CLAUDE.md` to note that
leaf modules inherit version constraints from the root and intentionally omit
`versions.tf`.

### IN-03: `ecr_image_uri` output description names a provisioner setting that does not match the convention's mapping form

**File:** `envs/prod/outputs.tf:61-64`
**Issue:** The description maps to provisioner `aws_ecr_image`, but the value is
`module.ecr.image_uri`, which is the bare `repository_url` (no tag). The
description elsewhere in the module (`modules/ecr/outputs.tf:2`) correctly notes
"the adapter appends the deployed tag." The root output description omits that
caveat, so a consumer reading only `envs/prod/outputs.tf` may assume the value
is a fully-qualified image reference including a tag, which it is not.
**Fix:** Add the tag-append caveat to the root output description for symmetry:
`"ECR repository URL for odoo-core (no tag; adapter appends the deployed tag) -> provisioner \`aws_ecr_image\`."`

---

_Reviewed: 2026-06-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
