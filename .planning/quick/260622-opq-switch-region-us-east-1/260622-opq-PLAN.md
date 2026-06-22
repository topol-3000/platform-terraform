---
quick_id: 260622-opq
slug: switch-region-us-east-1
date: 2026-06-22
status: complete
---

# Quick Task 260622-opq: Switch prod baseline default region to us-east-1

## Description

Move the entire prod baseline's default AWS region from `eu-central-1` to
`us-east-1`. Region is set in several independent places that must stay
consistent (the S3 backend region is a literal that cannot reference a
variable, and the `azs` defaults must match the region or `terraform apply`
fails with an invalid-AZ error — see `01-REVIEW.md` IN-01/IN-02).

## Tasks

1. Update region in all active config and keep region/AZ/backend consistent:
   - `envs/prod/backend.tf` — S3 backend `region` literal → `us-east-1`
   - `bootstrap/variables.tf` — `region` default → `us-east-1` (bucket region)
   - `envs/prod/variables.tf` — `region` default → `us-east-1`; `azs` default → `["us-east-1a","us-east-1b"]`
   - `modules/networking/variables.tf` — `azs` default → `["us-east-1a","us-east-1b"]`
   - `envs/prod/terraform.tfvars.example` — `region` → `us-east-1`

   - verify: `grep -rn eu-central-1 bootstrap envs modules --include=*.tf --include=*.tfvars*` returns nothing
   - verify: `make plan-check` passes (fmt -check, validate, non-empty plan)
   - done: plan shows `region = "us-east-1"` and `Plan: 9 to add`

## Out of scope

- `.planning/` historical artifacts (phase docs, REVIEW.md) — left as-is.
- Doc prose in `CLAUDE.md` / `README.md` mentioning the old default region.
