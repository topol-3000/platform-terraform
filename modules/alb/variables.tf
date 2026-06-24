variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "acm_cert_arn" {
  description = "ARN of the wildcard ACM certificate for the HTTPS:443 listener."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the ALB (across >=2 AZs). Sourced from module.networking.private_subnet_ids."
  type        = list(string)
}

variable "security_group_id" {
  description = "ALB security group ID (allows ingress 80/443 from internet). Sourced from module.networking.alb_security_group_id."
  type        = string
}
