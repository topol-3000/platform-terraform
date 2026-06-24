# Outputs for the route53 module. Uncomment / add as resources are implemented;
# envs/prod/outputs.tf re-exports the ones the provisioner adapter consumes.

output "hosted_zone_id" {
  description = "Route53 hosted zone ID -> provisioner `aws_hosted_zone_id`."
  value       = aws_route53_zone.main.zone_id
}
