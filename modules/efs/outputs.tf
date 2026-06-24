# Outputs for the efs module. Uncomment / add as resources are implemented;
# envs/prod/outputs.tf re-exports the ones the provisioner adapter consumes.

output "efs_id" {
  description = "Shared EFS filesystem id -> provisioner `aws_efs_id`."
  value       = aws_efs_file_system.main.id
}
