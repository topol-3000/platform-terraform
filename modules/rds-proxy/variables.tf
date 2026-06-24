variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

# Core gate (D-04): all proxy resources are count-gated behind this flag.
variable "enable_rds_proxy" {
  description = "Enable the RDS Proxy. Set true at ~30 active tenants when connection exhaustion risk arises."
  type        = bool
  default     = false
}

# Safe empty defaults below — the module call can omit these when enable_rds_proxy = false;
# envs/prod will always pass real values when the flag is on.

variable "db_instance_identifier" {
  description = "RDS instance identifier to attach the proxy to. Sourced from module.rds_tenant.identifier."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for the RDS Proxy ENIs."
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC id for the proxy security group."
  type        = string
  default     = ""
}

variable "task_security_group_id" {
  description = "Security group id for ECS tasks. Proxy SG allows 5432 ingress from this SG only."
  type        = string
  default     = ""
}

variable "master_username" {
  description = "RDS master username. Stored in the Secrets Manager secret for proxy auth."
  type        = string
  default     = "odoo_master"
}

variable "master_password" {
  description = "RDS master password (sensitive). Stored in the Secrets Manager secret for proxy auth."
  type        = string
  sensitive   = true
  default     = ""
}
