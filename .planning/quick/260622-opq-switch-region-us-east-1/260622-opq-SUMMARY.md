---
quick_id: 260622-opq
slug: switch-region-us-east-1
date: 2026-06-22
status: complete
---

# Quick Task 260622-opq: Switch prod baseline default region to us-east-1 — Summary

## What changed

Default AWS region moved from `eu-central-1` → `us-east-1` across all active
Terraform config. Region/AZ/backend kept consistent (the two traps from
`01-REVIEW.md`):

| File | Change |
|------|--------|
| `envs/prod/backend.tf` | S3 backend `region` literal → `us-east-1` |
| `bootstrap/variables.tf` | `region` default → `us-east-1` (state bucket region) |
| `envs/prod/variables.tf` | `region` default → `us-east-1`; `azs` default → `["us-east-1a","us-east-1b"]` |
| `modules/networking/variables.tf` | `azs` default → `["us-east-1a","us-east-1b"]` |
| `envs/prod/terraform.tfvars.example` | `region` → `us-east-1` |

## Verification

- `grep -rn eu-central-1` over `bootstrap/ envs/ modules/` (.tf + .tfvars*): no matches.
- `make plan-check` (offline gate) passed: `terraform fmt -check`, `validate`, and
  `Plan: 9 to add, 0 to change, 0 to destroy` with `region = "us-east-1"` on the VPC.

## Notes / not done

- `.planning/` historical artifacts (phase REVIEW/CONTEXT/etc.) and doc prose in
  `CLAUDE.md` / `README.md` still mention `eu-central-1` as the old default —
  intentionally left untouched (history, not active config).
- No `terraform apply` run (code-complete milestone only). The AZ defaults now
  resolve in us-east-1, but real AZ availability is only proven on a live apply.
- Local AWS CLI default region is still `us-east-1` already — consistent.
