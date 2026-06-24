# Module: alb
# Purpose: Shared internet-facing Application Load Balancer with HTTP→HTTPS redirect and HTTPS termination.
#
# SEED-001 note: idle_timeout > 60 required for Odoo longpoll (~50s). healthCheckGracePeriod >= 240s
# for first-boot init — that setting is adapter-owned (ECS service), not declared here.
#
# STATUS: implemented.
# See ../../../provisioner/.planning/seeds/SEED-001-aws-real-deployment.md

# Shared internet-facing ALB — HTTPS termination and HTTP→HTTPS redirect for all tenant subdomains.
# idle_timeout > 60 required for Odoo longpoll (~50s); must be on aws_lb NOT aws_lb_listener.
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  idle_timeout               = 120 # > 60: Odoo longpoll ~50s guard (SEED-001)
  enable_deletion_protection = false
  enable_http2               = true
  drop_invalid_header_fields = true
  # No access_logs block — deferred hardening (D-04); no S3 bucket provisioned this phase.

  tags = { Name = "${var.name_prefix}-alb" }
}

# HTTP:80 — redirects all traffic to HTTPS:443 with 301. No ssl_policy or certificate_arn on HTTP listeners.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS:443 — TLS termination. default_action is 503 because no tenant target groups exist yet;
# the provisioner adapter attaches per-tenant host rules to this listener at provision time.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_cert_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "No tenant provisioned"
      status_code  = "503"
    }
  }
}
