# Phase 2: Container platform - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-23
**Phase:** 2-container-platform
**Areas discussed:** GHCR credential / ECR approach, image_uri offline construction, ECS scope, ECR naming

---

## GHCR credential → ECR approach (pivotal)

Initial question — how to model the GHCR upstream credential for a pull-through cache:

| Option | Description | Selected |
|--------|-------------|----------|
| TF creates the Secrets Manager secret | Module creates `aws_secretsmanager_secret` (`ecr-pullthroughcache/` prefix); cache rule references `credential_arn` | |
| Credential ARN as a variable | Secret provisioned out-of-band; module takes `credential_secret_arn` input | |
| Discuss the tradeoff | — | ✓ |

**User's response:** "I do not know the best solution… I use GHCR by default and maybe it is better to use image storage by AWS if it is possible; moreover, in the future I think we will close our repos and make them private."

This reframed the question to **pull-through cache vs managed ECR repository**:

| Option | Description | Selected |
|--------|-------------|----------|
| Direct ECR repository (Recommended) | `aws_ecr_repository` for odoo-core; CI pushes to ECR; no GHCR dependency, no credential, `image_uri = repository_url`. Changes ECR-01. | ✓ |
| Keep GHCR pull-through cache | Honor ECR-01/SEED-001; requires GHCR PAT in Secrets Manager + account_id var | |
| Both: repo now, cache later | Build the repo now; note pull-through as deferred | |

**User's choice:** Direct ECR repository.
**Notes:** Aligns with the user's stated direction (AWS-native storage, private source repos). Also dissolves the credential problem and the offline-`image_uri` problem at once. Captured as D-01/D-02/D-03; ECR-01 (REQUIREMENTS.md) and the Phase 2 roadmap criterion were amended to match.

---

## image_uri offline construction

| Option | Description | Selected |
|--------|-------------|----------|
| account_id as a variable | Interpolate `<acct>.dkr.ecr…` URI from an input var | |
| Allow aws_caller_identity | Use STS data source; relax the offline gate | |
| Discuss it (best practices) | — | ✓ |

**User's choice:** "let's use best practices here."
**Notes:** Best practice = derive `image_uri` from the repository resource attribute `repository_url` (D-02). With the managed-repo decision (D-01) this needs no account-id var and no STS call, so the offline `make plan-check` gate (Phase 1 D-06) stays intact.

---

## ECS scope

| Option | Description | Selected |
|--------|-------------|----------|
| Cluster + Fargate providers | `aws_ecs_cluster` + capacity providers (FARGATE + FARGATE_SPOT) + Container Insights | ✓ |
| Bare cluster only | Just `aws_ecs_cluster` exporting `cluster_arn` | |
| Discuss it | — | |

**User's choice:** Cluster + Fargate providers.
**Notes:** Captured as D-04/D-05.

---

## ECR naming

| Option | Description | Selected |
|--------|-------------|----------|
| Discuss / I'll provide | User supplies GHCR org + ECR prefix | |
| Sensible defaults + TODO | — | |
| Skip — planner's discretion | Low-stakes naming; follow `name_prefix` conventions | ✓ |

**User's choice:** Skip — planner's discretion.
**Notes:** Moot for the GHCR namespace given the managed-repo decision; ECR repo name left to the planner under `name_prefix` conventions.

## Claude's Discretion

- ECR repo label/name under `name_prefix`; repository hardening defaults (scan-on-push, tag mutability, encryption, untagged-image lifecycle policy).
- ECS cluster setting style (containerInsights `enabled` vs `enhanced`; default capacity-provider strategy).
- `count`/`for_each` style and resource ordering.

## Deferred Ideas

- GHCR pull-through cache (dropped in favor of managed repo; re-open only to mirror an external source of truth).
- CI/CD build-and-push pipeline for `odoo-core` (out of Terraform baseline scope).
- ECR replication / KMS CMK encryption (hardening beyond MVP).
- VPC endpoints for ECR (api/dkr) + S3 (no-NAT pull path; networking-hardening pass).
