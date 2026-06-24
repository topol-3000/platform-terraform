output "endpoint" {
  description = "Control-plane RDS endpoint -> provisioner `aws_control_plane_rds_endpoint`."
  value       = aws_db_instance.control_plane.endpoint
}

output "security_group_id" {
  description = "Control-plane RDS security group id."
  value       = aws_security_group.cp_rds.id
}
