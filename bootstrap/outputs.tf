output "state_bucket_name" {
  description = "Name of the S3 state bucket. Use this in envs/*/backend.tf."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket."
  value       = aws_s3_bucket.tfstate.arn
}

output "region" {
  description = "Region the state bucket lives in."
  value       = var.region
}
