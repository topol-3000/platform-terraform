# Roadmap: platform-terraform

## Milestones

- ✅ **v1.0 Networking** — Phase 1 (shipped 2026-06-19)
- ✅ **v1.1 Complete the shared AWS baseline** — Phases 2-5 (shipped 2026-06-24) → [archive](milestones/v1.1-ROADMAP.md)

## Phases

<details>
<summary>✅ v1.0 Networking (Phase 1) — SHIPPED 2026-06-19</summary>

- [x] Phase 1: Networking module (2/2 plans) — completed 2026-06-19

</details>

<details>
<summary>✅ v1.1 Complete the shared AWS baseline (Phases 2-5) — SHIPPED 2026-06-24</summary>

Implemented, wired, and contract-exported the 10 remaining `modules/*` in the locked SEED-001 build order; `make plan-check` green at 36 resources, full provisioner output contract satisfied. Full detail: [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md).

- [x] Phase 2: Container platform (3/3 plans) — completed 2026-06-23
- [x] Phase 3: Databases and secrets (5/5 plans) — completed 2026-06-24
- [x] Phase 4: Shared filesystem (2/2 plans) — completed 2026-06-24
- [x] Phase 5: TLS and routing (3/3 plans) — completed 2026-06-24

</details>

### 📋 Next milestone (planned)

Define via `/gsd-new-milestone`. Candidates: live `terraform apply`, CI/CD + policy scanning (tfsec/checkov/Terratest), `envs/staging`.

## Progress

| Phase                    | Milestone | Plans Complete | Status   | Completed  |
| ------------------------ | --------- | -------------- | -------- | ---------- |
| 1. Networking module     | v1.0      | 2/2            | Complete | 2026-06-19 |
| 2. Container platform    | v1.1      | 3/3            | Complete | 2026-06-23 |
| 3. Databases and secrets | v1.1      | 5/5            | Complete | 2026-06-24 |
| 4. Shared filesystem     | v1.1      | 2/2            | Complete | 2026-06-24 |
| 5. TLS and routing       | v1.1      | 3/3            | Complete | 2026-06-24 |
