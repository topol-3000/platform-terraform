# Roadmap: platform-terraform

## Overview

This is a single-milestone roadmap. The milestone scope is the `networking` Terraform module — the foundation every other shared-baseline module consumes (SEED-001 build order: `networking → ecr → ecs → rds-* → efs/acm/alb/route53/ssm`). One phase implements the VPC, public subnets (no NAT gateway), and the ALB/task security groups, then wires the module into `envs/prod` and exports the four identifiers the provisioner's `AwsDeploymentAdapter` depends on. Verification is code-complete only: `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan` in `envs/prod` — no `terraform apply`, no AWS spend. The remaining nine modules are tracked as v2 future milestones, not phases in this roadmap.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Networking module** - VPC, public subnets (no NAT), ALB + task security groups, wired into envs/prod with a clean non-empty plan

## Phase Details

### Phase 1: Networking module
**Goal**: `modules/networking` is fully implemented and wired into `envs/prod`, producing a correct, well-formed, non-empty `terraform plan` that creates the VPC, public subnets, internet gateway/routing, and the ALB and task security groups — exporting the four identifiers (`vpc_id`, `private_subnet_ids`, `task_security_group_id`, `alb_security_group_id`) the provisioner contract requires.
**Depends on**: Nothing (first phase; bootstrap state backend already exists)
**Requirements**: NET-01, NET-02, NET-03, NET-04, NET-05, NET-06, NET-07
**Success Criteria** (what must be TRUE):
  1. `terraform plan` in `envs/prod` is non-empty and shows a VPC, public subnets across ≥2 AZs (with `map_public_ip_on_launch`), an internet gateway, a public route table with `0.0.0.0/0 → IGW`, and the two security groups — and **no NAT gateway** appears in the plan.
  2. The task security group's port-8069 ingress rule references the ALB security group's id as its source (not a CIDR block), confirming tasks on the public subnets are reachable on 8069 only via the ALB.
  3. The ALB security group permits ingress on 80 and 443 from `0.0.0.0/0` with egress open, and every created resource name carries the `var.name_prefix` prefix.
  4. The `module "networking"` call in `envs/prod/main.tf` and its four corresponding outputs in `envs/prod/outputs.tf` are uncommented and resolve — the public subnets are exported under the existing `private_subnet_ids` output name so the provisioner contract is unchanged.
  5. `terraform fmt -check` (recursive) and `terraform validate` both pass for the repo / `envs/prod`.
**Plans**: 2 plans

Plans:
- [ ] 01-01-PLAN.md — Implement modules/networking (VPC, public subnets, IGW/route table, ALB + task SGs, variables with validation, four outputs)
- [ ] 01-02-PLAN.md — Wire networking into envs/prod (vars + module call + output re-exports), add offline dummy-AWS make plan, run fmt/validate/non-empty-plan gate

## Progress

**Execution Order:**
Single phase — Phase 1.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Networking module | 0/2 | Not started | - |
