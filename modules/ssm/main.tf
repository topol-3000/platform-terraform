# Module: ssm
# Purpose: SSM Parameter Store SecureStrings (HMAC salt, RDS master creds)
#
# SEED-001 note: Parameter Store NOT Secrets Manager (~16-20x cheaper; HMAC passwords are reproducible).
#          RDS Proxy is the sole Secrets Manager exception — materialises only when enable_rds_proxy = true.

# Generate the tenant RDS master password at plan time — offline, no live AWS call required (D-01, D-03).
# Exclude characters that break Postgres connection strings (/ @ " and space).
resource "random_password" "tenant_rds" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# HMAC salt used by the provisioner to derive per-tenant token secrets.
# Reproducible: stored in SSM so it can be retrieved after rotation without data loss.
resource "random_password" "hmac_salt" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# SecureString with default AWS-managed key (alias/aws/ssm, D-09) — value written from
# random_password.result at apply time; lifecycle ignore_changes allows out-of-band rotation
# without Terraform drift (D-02).
resource "aws_ssm_parameter" "tenant_rds_password" {
  name  = "/${var.name_prefix}/rds/tenant/master-password"
  type  = "SecureString"
  value = random_password.tenant_rds.result
  # key_id omitted — uses default alias/aws/ssm (AWS-managed key, D-09)

  lifecycle {
    ignore_changes = [value] # Allow out-of-band rotation without Terraform drift (D-02)
  }

  tags = { Name = "${var.name_prefix}-rds-tenant-password" }
}

# HMAC salt stored as a SecureString so the provisioner can re-derive per-tenant token
# secrets after an HMAC key rotation without losing access to existing tokens.
resource "aws_ssm_parameter" "hmac_salt" {
  name  = "/${var.name_prefix}/hmac-salt"
  type  = "SecureString"
  value = random_password.hmac_salt.result
  # key_id omitted — uses default alias/aws/ssm (AWS-managed key, D-09)

  lifecycle {
    ignore_changes = [value] # Allow out-of-band rotation without Terraform drift (D-02)
  }

  tags = { Name = "${var.name_prefix}-hmac-salt" }
}
