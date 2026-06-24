# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.1 — Complete the shared AWS baseline

**Shipped:** 2026-06-24
**Phases:** 4 (Phases 2-5) | **Plans:** 13 | **Commits:** 82 (20 feat)

### What Was Built
- **Container platform** — managed ECR repo for `odoo-core` + shared ECS/Fargate cluster (Container Insights, FARGATE + FARGATE_SPOT)
- **Databases & secrets** — Single-AZ tenant RDS, count-gated RDS Proxy, isolated Multi-AZ control-plane RDS; SSM SecureStrings for all credentials
- **Shared filesystem** — encrypted EFS with per-AZ mount targets, NFS scoped to the task SG
- **TLS & routing** — wildcard ACM cert, ALB (HTTP→HTTPS, TLS 1.3, idle_timeout=120), Route53 hosted zone
- Full provisioner output contract: all 11 modules wired in `envs/prod`, `make plan-check` green at 36 resources

### What Worked
- **Offline `make plan-check` gate** caught wiring and contract errors at zero AWS cost after every phase — code-complete verification proved sufficient to ship the whole baseline confidently.
- **Per-module "networking pattern"** (implement → uncomment call → wire output → keep plan green) made each module a small, repeatable, independently-verifiable unit.
- **Pre-declaring variables before resource bodies** (from CONCERNS.md) avoided forward-reference breakage during wiring.
- **SG-reference-only scoping** as a uniform invariant (task←ALB, RDS←task, EFS←task) kept the no-NAT public-subnet posture safe across every module.

### What Was Inefficient
- **`milestone.complete` SDK accomplishment extraction** produced noise ("One-liner:", a stray filename) and counted Phase 1 (v1.0) into the v1.1 totals — required manual cleanup of MILESTONES.md.
- **v1.0 was never formally closed** via the milestone workflow, leaving phase/milestone accounting ambiguous at v1.1 close (had to disambiguate Phases 2-5 vs all 5).
- **Region drift** — a quick task switched the default region to us-east-1 but PROJECT.md Constraints still read eu-central-1 until this close; the doc lagged the code.

### Patterns Established
- Count-gated optional infrastructure (`enable_rds_proxy` + `try()` endpoint) — zero-resource until a scaling threshold, wired in advance.
- Module dir names hyphenated, module labels underscored (`modules/rds-control-plane` → `module "rds_control_plane"`).
- Makefile `plan-check` injects dummy `-var` values (e.g. `tenant_domain`) to keep the offline gate green without real inputs.

### Key Lessons
1. **Close milestones as you ship them** — formally archiving v1.0 when it shipped would have removed the phase-counting ambiguity at v1.1 close.
2. **Quick tasks that change locked constraints (region) must update PROJECT.md in the same change** — docs drifted from code for two days.
3. **Plan-only verification scales** — a 36-resource baseline was shipped with confidence on fmt/validate/plan alone; live apply is a deliberate, separable next step.

### Cost Observations
- Model mix: predominantly Opus 4.8 (quality profile)
- Notable: 13 plans across 4 phases in ~2 calendar days; the repeatable per-module pattern kept per-plan overhead low.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 Networking | 1 | 2 | Established the offline `make plan-check` gate and the per-module wiring pattern |
| v1.1 Baseline | 4 | 13 | Scaled the pattern across 10 modules; added count-gated optional infra and dummy-var plan injection |

### Top Lessons (Verified Across Milestones)

1. Offline plan-check (fmt + validate + non-empty plan) is sufficient verification for code-complete Terraform milestones — no apply required.
2. SG-reference-only ingress scoping is the load-bearing security invariant for the no-NAT public-subnet architecture.
