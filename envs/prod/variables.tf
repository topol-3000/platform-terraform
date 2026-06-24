variable "region" {
  description = "AWS region for the prod baseline. Must match the state bucket region."
  type        = string
  default     = "us-east-1"
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
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "azs" {
  description = "Availability zones to deploy public subnets into."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two AZs are required (future ALB needs >=2 subnets)."
  }
}

variable "enable_rds_proxy" {
  description = "Enable the RDS Proxy module. Set true at ~30 active tenants."
  type        = bool
  default     = false
}

variable "rds_instance_class" {
  description = "RDS instance class for both tenant and control-plane instances."
  type        = string
  default     = "db.t4g.small"
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version for all RDS instances."
  type        = string
  default     = "16"
}

variable "rds_allocated_storage" {
  description = "Initial allocated storage in GiB for each RDS instance."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling in GiB."
  type        = number
  default     = 100
}
