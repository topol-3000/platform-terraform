output "image_uri" {
  description = "ECR repository URL for the odoo-core image; the adapter appends the deployed tag."
  value       = aws_ecr_repository.odoo_core.repository_url
}
