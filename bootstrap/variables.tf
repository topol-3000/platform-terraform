variable "region" {
  description = "AWS region for the state bucket. Should match the region used by envs/*."
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally-unique name for the S3 bucket that holds Terraform remote state.
    If the default is taken, append a suffix (e.g. your AWS account id) and use
    the SAME value in envs/prod/backend.tf (or via `terraform init -backend-config`).
  EOT
  type        = string
  default     = "odoo-saas-tfstate"
}

variable "noncurrent_version_expiration_days" {
  description = "Delete noncurrent (overwritten) state versions after this many days."
  type        = number
  default     = 90
}
