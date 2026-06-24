# Sensitive pass-through outputs for inter-module wiring — raw random_password.result
# marked sensitive = true so the value is masked in plan output. These are consumed by
# modules/rds-tenant as master_password only; they must NEVER appear in
# envs/prod/outputs.tf (provisioner contract).

output "tenant_rds_password" {
  description = "Tenant RDS master password (sensitive). Passed to modules/rds-tenant as master_password only — never re-exported to provisioner."
  value       = random_password.tenant_rds.result
  sensitive   = true
}

# Non-sensitive name/ARN outputs for the provisioner contract — parameter names and ARNs
# allow the provisioner adapter to look up secrets at runtime without exposing raw values.

output "tenant_rds_password_name" {
  description = "SSM parameter name for the tenant RDS master password."
  value       = aws_ssm_parameter.tenant_rds_password.name
}

output "tenant_rds_password_arn" {
  description = "SSM parameter ARN for the tenant RDS master password."
  value       = aws_ssm_parameter.tenant_rds_password.arn
}

output "hmac_salt_name" {
  description = "SSM parameter name for the HMAC salt."
  value       = aws_ssm_parameter.hmac_salt.name
}

output "hmac_salt_arn" {
  description = "SSM parameter ARN for the HMAC salt."
  value       = aws_ssm_parameter.hmac_salt.arn
}
