terraform {
  required_version = ">= 1.11.0"

  # Bootstrap intentionally uses LOCAL state — it is what creates the S3 bucket
  # that every other config stores its state in. Run this once, by hand.
  # The resulting bootstrap/terraform.tfstate is small and non-secret; commit it.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "odoo-saas"
      ManagedBy = "terraform"
      Component = "tf-bootstrap"
    }
  }
}
