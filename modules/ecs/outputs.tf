output "cluster_arn" {
  description = "Shared ECS cluster ARN for the tenant Fargate fleet."
  value       = aws_ecs_cluster.main.arn
}
