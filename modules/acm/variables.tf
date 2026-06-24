variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"odoo-saas-prod\"."
  type        = string
}

variable "tenant_domain" {
  description = "Apex domain for the wildcard ACM certificate, e.g. \"saas.example.com\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.tenant_domain))
    error_message = "tenant_domain must be a valid apex domain, e.g. saas.example.com."
  }
}
