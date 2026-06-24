variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the control-plane RDS DB subnet group. Requires >=2 subnets in different AZs."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC id for the control-plane RDS security group."
  type        = string
}

variable "task_security_group_id" {
  description = "Security group id for ECS tasks. Control-plane RDS SG allows 5432 ingress from this SG only."
  type        = string
}

variable "master_password" {
  description = "Control-plane RDS master password (sensitive). Sourced from modules/ssm random_password output."
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS instance class for the control-plane PostgreSQL instance."
  type        = string
  default     = "db.t4g.small"
}

variable "engine_version" {
  description = "PostgreSQL engine version for the control-plane instance."
  type        = string
  default     = "16"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling in GiB."
  type        = number
  default     = 100
}
