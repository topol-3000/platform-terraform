# Phase 1: Networking module - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-19
**Phase:** 1-networking-module
**Areas discussed:** AZ & CIDR strategy, Plan-without-creds approach, SG egress posture, Variable defaults & tfvars

---

## AZ & CIDR strategy

### VPC CIDR and subnet layout

| Option | Description | Selected |
|--------|-------------|----------|
| 10.0.0.0/16, /20 subnets | 65k-address VPC, /20 public subnets (~4k IPs each) | ✓ |
| 10.0.0.0/16, /24 subnets | Smaller /24 public subnets (251 usable each) | |
| Make CIDR a variable | Expose vpc_cidr var with 10.0.0.0/16 default; cidrsubnet() | |

**User's choice:** 10.0.0.0/16 with /20 subnets (still parameterized via vpc_cidr + cidrsubnet).

### Availability Zone selection

| Option | Description | Selected |
|--------|-------------|----------|
| az_count variable, default 2 | AZ names from data.aws_availability_zones | |
| Hardcode 2 AZs (eu-central-1a/b) | Explicit names via variable, no data source | |
| azs list variable, no data source | Explicit list var, default [eu-central-1a, eu-central-1b] | ✓ |

**User's choice:** Explicit `azs` list variable, no data source.
**Notes:** No data source keeps `terraform plan` runnable offline — aligns with code-complete verification.

---

## Plan-without-creds approach

| Option | Description | Selected |
|--------|-------------|----------|
| Dummy env vars in Makefile | make plan exports dummy AWS creds + region | ✓ |
| Provider skip_* flags | skip_credentials_validation etc. in providers.tf | |
| Just document it | No change; rely on validate as the hard gate | |

**User's choice:** Dummy AWS env vars in the Makefile plan target.
**Notes:** Keeps providers.tf clean for real applies; no data sources + no state means no real AWS calls during plan.

---

## SG egress posture

### Egress rules

| Option | Description | Selected |
|--------|-------------|----------|
| Allow-all egress on both | 0.0.0.0/0 all-protocols on ALB SG and task SG | ✓ |
| Restrict task egress to 443 | Task SG egress limited to HTTPS | |
| You decide later | Allow-all now; note tightening as deferred | |

**User's choice:** Allow-all egress on both SGs.
**Notes:** Tasks need outbound to ECR/SSM/internet (no NAT = public). Egress tightening captured as a deferred hardening idea.

### ALB ingress ports

| Option | Description | Selected |
|--------|-------------|----------|
| Both 80 and 443 | Ingress 80 + 443 from 0.0.0.0/0 (redirect later) | ✓ |
| 443 only | HTTPS only; add 80 later | |

**User's choice:** Both 80 and 443.

---

## Variable defaults & tfvars

### Defaults for out-of-the-box plan

| Option | Description | Selected |
|--------|-------------|----------|
| Defaults in envs/prod | Prod-sensible defaults so make plan runs zero-edit | ✓ |
| Require terraform.tfvars | Force values via tfvars | |
| Module defaults only | Module carries defaults; envs/prod passes nothing | |

**User's choice:** Prod-sensible defaults in envs/prod.

### Module interface

| Option | Description | Selected |
|--------|-------------|----------|
| Add full var set now | name_prefix, vpc_cidr, azs (+needed) with validation | ✓ |
| Minimal vars | Only strictly-needed inputs; expand later | |

**User's choice:** Add the full variable set now, with validation blocks.

---

## Claude's Discretion

- Subnet `for_each` vs `count` implementation style.
- Whether subnet sizing newbits is a variable or hardcoded `/20` via `cidrsubnet`.
- `aws_route` resource vs inline route in `aws_route_table`.
- Tag map composition beyond `name_prefix`.

## Deferred Ideas

- Egress tightening (task SG → 443 only) — future hardening pass.
- VPC endpoints (S3/ECR/SSM/interface) — cleaner no-NAT outbound; later phase.
- Private subnets — only when RDS lands (future milestone).
- Provider lock file + tfsec/CI — repo-wide CONCERNS.md items, not this milestone.
