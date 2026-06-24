output "vpc_id" {
  description = "VPC id for downstream modules (rds, ecs, alb)."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the public subnets tenant tasks run in."
  value       = aws_subnet.public[*].id
}

output "task_security_group_id" {
  description = "Security group id for tenant ECS tasks."
  value       = aws_security_group.task.id
}

output "alb_security_group_id" {
  description = "Security group id for the shared ALB."
  value       = aws_security_group.alb.id
}

output "private_subnets_by_az" {
  description = "Map of AZ to public subnet id for EFS mount target per-AZ placement."
  value       = { for i, az in var.azs : az => aws_subnet.public[i].id }
}
