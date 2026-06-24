# Module: route53
# Purpose: Public Route53 hosted zone for the tenant domain.
#
# SEED-001 note: Per-tenant records created by the adapter (or a DNS step) at provision time.
#
# STATUS: implemented.
# See ../../../provisioner/.planning/seeds/SEED-001-aws-real-deployment.md

# Public hosted zone for tenant subdomains. No records declared here — the provisioner
# adapter adds per-tenant records at provision time (SEED-001; D-03).
resource "aws_route53_zone" "main" {
  name          = var.tenant_domain
  force_destroy = false
}
