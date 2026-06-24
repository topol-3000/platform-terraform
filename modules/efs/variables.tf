variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "vpc_id" {
  description = "VPC id for the EFS security group."
  type        = string
}

variable "task_security_group_id" {
  description = "Security group id for tenant ECS tasks. EFS SG allows NFS (2049) ingress from this SG only."
  type        = string
}

variable "subnet_ids_by_az" {
  description = "Map of AZ to public subnet id for EFS mount target per-AZ placement."
  type        = map(string)
}
