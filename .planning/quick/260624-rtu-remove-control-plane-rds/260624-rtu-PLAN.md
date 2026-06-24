---
phase: quick-260624-rtu
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - modules/rds-control-plane/main.tf
  - modules/rds-control-plane/variables.tf
  - modules/rds-control-plane/outputs.tf
  - modules/ssm/main.tf
  - modules/ssm/outputs.tf
  - envs/prod/main.tf
  - envs/prod/outputs.tf
  - README.md
autonomous: true
requirements: [remove-control-plane-rds]

must_haves:
  truths:
    - "modules/rds-control-plane/ directory does not exist"
    - "envs/prod/main.tf has no rds_control_plane module block"
    - "envs/prod/outputs.tf has no control_plane_rds_endpoint output"
    - "modules/ssm/main.tf has no cp_rds random_password or aws_ssm_parameter resources"
    - "modules/ssm/outputs.tf has no cp_rds_password, cp_rds_password_name, or cp_rds_password_arn outputs"
    - "terraform fmt -check passes (no diff)"
    - "terraform validate passes"
    - "terraform plan (offline via make plan-check) is non-empty and references no control-plane resources"
  artifacts:
    - path: "envs/prod/main.tf"
      provides: "Module wiring without rds_control_plane block"
    - path: "envs/prod/outputs.tf"
      provides: "Provisioner contract without control_plane_rds_endpoint"
    - path: "modules/ssm/main.tf"
      provides: "SSM resources for tenant_rds and hmac_salt only"
    - path: "modules/ssm/outputs.tf"
      provides: "SSM outputs for tenant credentials and hmac_salt only"
    - path: "README.md"
      provides: "Updated layout tree, outputs table, module status table — no control-plane rows"
  key_links:
    - from: "modules/ssm/main.tf"
      to: "envs/prod/main.tf"
      via: "module.ssm.cp_rds_password reference removed"
      pattern: "cp_rds_password"
    - from: "modules/rds-control-plane/"
      to: "envs/prod/main.tf"
      via: "module block removed"
      pattern: "rds_control_plane"
---

<objective>
Remove the `rds-control-plane` module and all references to it. The provisioner
(control-plane) will be hosted independently and owns its own operational database.
This repo provisions only tenant-facing shared infrastructure.

Purpose: Eliminate infrastructure that belongs to a different operational boundary.
Output: A clean, passing `make plan-check` with no control-plane resources anywhere
in the config.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Remove control-plane Terraform resources and module wiring</name>
  <files>
    modules/rds-control-plane/main.tf,
    modules/rds-control-plane/variables.tf,
    modules/rds-control-plane/outputs.tf,
    modules/ssm/main.tf,
    modules/ssm/outputs.tf,
    envs/prod/main.tf,
    envs/prod/outputs.tf
  </files>
  <action>
Delete the entire `modules/rds-control-plane/` directory (main.tf, variables.tf, outputs.tf).

In `modules/ssm/main.tf`, remove both the `resource "random_password" "cp_rds"` block
(lines 17-21) and the `resource "aws_ssm_parameter" "cp_rds_password"` block (lines 49-60),
including their preceding comment lines. The two remaining resources —
`random_password.tenant_rds`, `random_password.hmac_salt`,
`aws_ssm_parameter.tenant_rds_password`, and `aws_ssm_parameter.hmac_salt` — stay
completely intact.

In `modules/ssm/outputs.tf`, remove the `cp_rds_password` output (lines 12-15),
the `cp_rds_password_name` output (lines 31-34), and the `cp_rds_password_arn` output
(lines 35-38), along with any associated comment lines. The retained outputs are:
`tenant_rds_password`, `tenant_rds_password_name`, `tenant_rds_password_arn`,
`hmac_salt_name`, `hmac_salt_arn`.

In `envs/prod/main.tf`, remove the entire `module "rds_control_plane"` block (lines 69-81)
including the preceding comment line "# Separate Multi-AZ PostgreSQL...". The surrounding
blocks (`module "rds_proxy"` ending at line 67, and `# --- 6. Filestore...` section
starting at line 83) must remain untouched.

In `envs/prod/outputs.tf`, remove the `output "control_plane_rds_endpoint"` block
(lines 46-49). The preceding `rds_proxy_endpoint` output and the following `efs_id`
output stay intact.

After edits, run `terraform fmt -recursive` from the repo root to canonicalise
formatting (per CLAUDE.md: `make fmt` or `cd envs/prod && terraform fmt -recursive ../..`).
Ensure `~/.local/bin` is on PATH so the `terraform` binary resolves.
  </action>
  <verify>
    <automated>
      grep -r "rds_control_plane\|cp_rds\|control.plane.rds\|control_plane_rds" \
        modules/ssm/ envs/prod/main.tf envs/prod/outputs.tf 2>/dev/null \
        | grep -v '^Binary' && echo "FAIL: control-plane references remain" || echo "PASS: no control-plane references"
    </automated>
    <automated>test ! -d modules/rds-control-plane && echo "PASS: directory deleted" || echo "FAIL: directory still exists"</automated>
  </verify>
  <done>
    The `modules/rds-control-plane/` directory is gone. No occurrence of `cp_rds`,
    `rds_control_plane`, or `control_plane_rds` in `modules/ssm/`, `envs/prod/main.tf`,
    or `envs/prod/outputs.tf`. `terraform fmt -check` reports no diff.
  </done>
</task>

<task type="auto">
  <name>Task 2: Update README — drop all control-plane references</name>
  <files>README.md</files>
  <action>
Make three targeted edits to README.md:

1. Layout tree (around line 34): Remove the line
   `│   ├── rds-control-plane/ # separate control-plane RDS (Multi-AZ, 99.9% SLA)`
   Leave all other tree lines intact.

2. "Outputs -> provisioner settings" table (around line 166): Remove the row
   `| control_plane_rds_endpoint | aws_control_plane_rds_endpoint |`
   Leave all other table rows intact.

3. "Module status" table (around line 186): Remove the row
   `| rds-control-plane | Separate Multi-AZ PostgreSQL for control-plane (provisioner) data | complete |`
   Update the status banner (line 16) from "All 11 modules" to "All 10 modules" since
   there are now 10 implemented modules.

Also update the Configuration table (around line 143): remove or update the note
`Applies to both tenant and control-plane RDS` from the `rds_instance_class` row
description — change it to `Applies to the tenant RDS instance.` since control-plane
is gone.

No other README content changes. Do not touch CLAUDE.md or any `.planning/` files.
  </action>
  <verify>
    <automated>
      grep -n "rds-control-plane\|control_plane_rds\|control-plane RDS\|11 modules" README.md \
        && echo "FAIL: control-plane references remain in README" || echo "PASS: README clean"
    </automated>
  </verify>
  <done>
    README.md contains no references to `rds-control-plane`, `control_plane_rds_endpoint`,
    or "control-plane RDS". Module count updated to 10. Configuration table note updated.
  </done>
</task>

<task type="auto">
  <name>Task 3: Run offline plan-check gate</name>
  <files></files>
  <action>
Run the offline verification gate. Ensure `~/.local/bin` is on PATH (terraform lives there):

  export PATH="$HOME/.local/bin:$PATH"
  make plan-check

This runs `terraform fmt -check`, `terraform validate`, and a non-empty `terraform plan`
using a local backend override (no S3 or AWS credentials required). The plan output must
be non-empty and must not reference any `rds_control_plane` or `cp_rds` resources.

If `fmt -check` fails, run `make fmt` first and re-run `make plan-check`.
  </action>
  <verify>
    <automated>export PATH="$HOME/.local/bin:$PATH" && make plan-check 2>&1 | tail -20</automated>
  </verify>
  <done>
    `make plan-check` exits 0. Output shows `terraform fmt -check` clean,
    `terraform validate` success, and a non-empty plan with zero control-plane
    resource references.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Local repo -> Terraform state | Removal of module wiring; no live AWS changes (code-complete milestone) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-rtu-01 | Tampering | modules/ssm/main.tf | mitigate | Verify grep gate confirms no cp_rds resources remain; `terraform validate` catches dangling references |
| T-rtu-SC | Tampering | npm/pip/cargo installs | accept | No package manager installs in this task |
</threat_model>

<verification>
All three tasks must pass before marking the quick task complete:

1. `test ! -d modules/rds-control-plane` exits 0.
2. `grep -r "rds_control_plane\|cp_rds\|control_plane_rds" modules/ssm/ envs/prod/` returns no matches.
3. `grep -n "rds-control-plane\|control_plane_rds" README.md` returns no matches.
4. `make plan-check` (with `~/.local/bin` on PATH) exits 0 with a non-empty plan.
</verification>

<success_criteria>
- `modules/rds-control-plane/` directory does not exist.
- `modules/ssm/main.tf` contains exactly two `random_password` resources (tenant_rds, hmac_salt) and two `aws_ssm_parameter` resources (tenant_rds_password, hmac_salt).
- `modules/ssm/outputs.tf` has no `cp_rds_*` outputs.
- `envs/prod/main.tf` has no `module "rds_control_plane"` block.
- `envs/prod/outputs.tf` has no `control_plane_rds_endpoint` output.
- `README.md` module count is 10, no control-plane rows in any table.
- `make plan-check` exits 0.
</success_criteria>

<output>
Create `.planning/quick/260624-rtu-remove-control-plane-rds/260624-rtu-01-SUMMARY.md` when done.
</output>
