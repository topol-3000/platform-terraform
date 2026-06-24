output "endpoint" {
  description = "Shared tenant RDS endpoint -> provisioner `aws_shared_rds_endpoint`."
  value       = aws_db_instance.tenant.endpoint
}

output "identifier" {
  description = "RDS instance identifier. Passed to rds-proxy as db_instance_identifier."
  value       = aws_db_instance.tenant.identifier
}

output "security_group_id" {
  description = "RDS tenant security group id. Passed to rds-proxy for proxy SG ingress wiring."
  value       = aws_security_group.rds_tenant.id
}

output "db_resource_id" {
  description = "RDS resource id (DbiResourceId). Used for IAM authentication if added later."
  value       = aws_db_instance.tenant.resource_id
}
