# Outputs for the alb module. Uncomment / add as resources are implemented;
# envs/prod/outputs.tf re-exports the ones the provisioner adapter consumes.

output "listener_arn" {
  description = "HTTPS:443 listener ARN -> provisioner `aws_alb_listener_arn`."
  value       = aws_lb_listener.https.arn
}
