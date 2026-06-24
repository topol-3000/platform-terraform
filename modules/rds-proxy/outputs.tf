# try() is canonical for count-gated resources — do NOT use a length() ternary.
# The try() form does not evaluate the index expression when count = 0 (D-06).
output "endpoint" {
  description = "RDS Proxy endpoint -> provisioner `aws_rds_proxy_endpoint`. Null when enable_rds_proxy is false."
  value       = try(aws_db_proxy.this[0].endpoint, null)
}
