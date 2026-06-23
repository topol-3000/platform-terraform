---
phase: 02-container-platform
plan: "02"
subsystem: ecs
tags: [ecs, fargate, container-platform, capacity-providers, container-insights]
dependency_graph:
  requires: []
  provides: [modules/ecs cluster_arn output]
  affects: [envs/prod — wired in plan 02-03]
tech_stack:
  added: []
  patterns: [aws_ecs_cluster_capacity_providers multi-resource-same-label, name_prefix-named resources]
key_files:
  created: []
  modified:
    - modules/ecs/main.tf
    - modules/ecs/outputs.tf
decisions:
  - "D-04 honored: aws_ecs_cluster + aws_ecs_cluster_capacity_providers wiring FARGATE + FARGATE_SPOT with Container Insights enabled"
  - "D-05 honored: cluster is name_prefix-named; exports cluster_arn"
  - "D-07 honored: no data sources, no new variables — plan remains fully offline"
  - "containerInsights value chosen as 'enabled' (not 'enhanced') for predictable cost while satisfying T-02-05 observability requirement"
  - "default_capacity_provider_strategy included: FARGATE base=1 (primary), FARGATE_SPOT base=0 (secondary)"
metrics:
  duration: "2m"
  completed: "2026-06-23T10:33:07Z"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 2
---

# Phase 02 Plan 02: ECS Module Implementation Summary

Shared ECS/Fargate cluster with FARGATE + FARGATE_SPOT capacity providers and Container Insights, exporting `cluster_arn`.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Implement shared ECS cluster, capacity-provider association, and outputs | 33b490f | modules/ecs/main.tf, modules/ecs/outputs.tf |

## What Was Built

`modules/ecs/main.tf` implements two resources:

1. `aws_ecs_cluster.main` — named `${var.name_prefix}-cluster`, with `setting { name = "containerInsights" value = "enabled" }` and a `Name`-only tag.

2. `aws_ecs_cluster_capacity_providers.main` — shares the `main` label (multi-resource-same-label pattern from `bootstrap/main.tf`). Wires `FARGATE` and `FARGATE_SPOT` to the cluster via `cluster_name = aws_ecs_cluster.main.name`. Includes a `default_capacity_provider_strategy` with FARGATE as primary (base=1, weight=1) and FARGATE_SPOT as secondary (base=0, weight=1).

`modules/ecs/outputs.tf` exports a single output:
- `cluster_arn` — `aws_ecs_cluster.main.arn`, consumed by `envs/prod` as `ecs_cluster_arn` → provisioner `aws_ecs_cluster`.

## Verification

All plan verification checks pass:
- `resource "aws_ecs_cluster"` present with `name_prefix}-cluster`
- `containerInsights` setting present
- `resource "aws_ecs_cluster_capacity_providers"` present with `FARGATE_SPOT`
- `cluster_arn` output exports `.arn` attribute
- No `data` blocks introduced
- `terraform fmt -check modules/ecs` exits 0

Note: Full offline gate (`make plan-check`) is verified in plan 02-03 after `envs/prod` wiring.

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. The `containerInsights = "enabled"` setting satisfies T-02-05 (Repudiation mitigation) as specified in the plan's threat register.

## Self-Check

- [x] `modules/ecs/main.tf` exists and contains both resources
- [x] `modules/ecs/outputs.tf` exports `cluster_arn`
- [x] Commit `33b490f` exists

## Self-Check: PASSED
