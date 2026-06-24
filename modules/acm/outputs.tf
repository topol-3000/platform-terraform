# Outputs for the acm module. Uncomment / add as resources are implemented;
# envs/prod/outputs.tf re-exports the ones the provisioner adapter consumes.

output "cert_arn" {
  description = "Wildcard ACM certificate ARN -> provisioner `aws_acm_cert_arn`."
  value       = aws_acm_certificate.wildcard.arn
}
