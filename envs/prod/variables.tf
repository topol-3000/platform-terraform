variable "region" {
  description = "AWS region for the prod baseline. Must match the state bucket region."
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (used in tags and resource names)."
  type        = string
  default     = "prod"
}

variable "project" {
  description = "Project prefix for resource names."
  type        = string
  default     = "odoo-saas"
}

variable "tenant_domain" {
  description = <<-EOT
    Apex domain that tenant instances live under, e.g. "saas.example.com".
    Instances are served at {slug}.{tenant_domain} via host-based ALB routing,
    behind a wildcard ACM cert for *.{tenant_domain}.
  EOT
  type        = string
  default     = "" # TODO: set in terraform.tfvars before building route53/acm/alb
}

variable "vpc_cidr" {
  description = "CIDR block for the prod VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to deploy public subnets into."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}
