provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "odoo-saas"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "platform-terraform"
    }
  }
}
