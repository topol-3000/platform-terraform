# Identifiers consumed by the provisioner's AwsDeploymentAdapter as
# DEPLOYMENT_ADAPTER=aws settings. Uncomment each as its module lands.
#
# See provisioner/src/provisioning_worker/settings.py for the matching fields.

# output "ecs_cluster_arn" {
#   description = "Shared ECS cluster ARN -> provisioner `aws_ecs_cluster`."
#   value       = module.ecs.cluster_arn
# }

# output "private_subnet_ids" {
#   description = "Subnets for tenant tasks -> provisioner `aws_subnets`."
#   value       = module.networking.private_subnet_ids
# }

# output "task_security_group_id" {
#   description = "SG for tenant tasks -> provisioner `aws_security_groups`."
#   value       = module.networking.task_security_group_id
# }

# output "alb_listener_arn" {
#   description = "ALB HTTPS listener ARN -> provisioner `aws_alb_listener_arn`."
#   value       = module.alb.listener_arn
# }

# output "tenant_rds_endpoint" {
#   description = "Shared tenant RDS endpoint -> provisioner `aws_shared_rds_endpoint`."
#   value       = module.rds_tenant.endpoint
# }

# output "rds_proxy_endpoint" {
#   description = "RDS Proxy endpoint -> provisioner `aws_rds_proxy_endpoint`."
#   value       = module.rds_proxy.endpoint
# }

# output "efs_id" {
#   description = "Shared EFS id -> provisioner `aws_efs_id`."
#   value       = module.efs.efs_id
# }

# output "hosted_zone_id" {
#   description = "Route53 zone id -> provisioner `aws_hosted_zone_id`."
#   value       = module.route53.hosted_zone_id
# }

# output "acm_cert_arn" {
#   description = "Wildcard ACM cert ARN -> provisioner `aws_acm_cert_arn`."
#   value       = module.acm.cert_arn
# }

# output "ecr_image_uri" {
#   description = "ECR pull-through image URI -> provisioner `aws_ecr_image`."
#   value       = module.ecr.image_uri
# }
