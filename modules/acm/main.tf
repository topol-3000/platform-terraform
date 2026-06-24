# Module: acm
# Purpose: Wildcard ACM certificate for *.{tenant_domain} with DNS validation.
#
# SEED-001 note: Custom domains later are additive: per-domain SNI cert + host-rule.
#
# STATUS: implemented.
# See ../../../provisioner/.planning/seeds/SEED-001-aws-real-deployment.md

# Wildcard ACM certificate for *.{tenant_domain} — DNS validation; bare cert only (D-02).
# No aws_acm_certificate_validation resource (validation chain deferred; offline-plan-safe).
resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.tenant_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
