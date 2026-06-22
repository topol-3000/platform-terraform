terraform {
  # Remote state in S3 with NATIVE locking (Terraform >= 1.11) — no DynamoDB.
  #
  # The bucket is created by ../../bootstrap. If you changed the bucket name
  # there, override it at init time instead of editing this file:
  #   terraform init -backend-config="bucket=odoo-saas-tfstate-<suffix>"
  backend "s3" {
    bucket       = "odoo-saas-tfstate"
    key          = "prod/baseline.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
