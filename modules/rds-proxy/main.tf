# Module: rds-proxy
# Purpose: RDS Proxy fronting the shared tenant RDS instance.
#
# SEED-001 note: Activate by ~30 active tenants. Validate Odoo bus LISTEN/NOTIFY through
#          the proxy (connection-pinning risk) before relying on it in production.
#          All resources gated behind var.enable_rds_proxy (default false).
#          The Secrets Manager secret here is the sole exception to the SSM-only rule
#          per D-05 — RDS Proxy auth cannot read SSM directly.

# RDS Proxy auth requires a Secrets Manager secret — it cannot read SSM directly.
# This is the sole sanctioned exception to the SSM-only rule (D-05); only materialises
# when enable_rds_proxy = true.
resource "aws_secretsmanager_secret" "proxy_auth" {
  count       = var.enable_rds_proxy ? 1 : 0
  name        = "${var.name_prefix}-rds-proxy-auth"
  description = "Credentials for RDS Proxy authentication. Sole Secrets Manager usage in this repo (RDS Proxy auth cannot use SSM)."

  tags = { Name = "${var.name_prefix}-rds-proxy-auth" }
}

resource "aws_secretsmanager_secret_version" "proxy_auth" {
  count     = var.enable_rds_proxy ? 1 : 0
  secret_id = aws_secretsmanager_secret.proxy_auth[0].id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
  })
}

# IAM role that allows the RDS service to read the Secrets Manager secret for proxy auth.
resource "aws_iam_role" "proxy" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${var.name_prefix}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.name_prefix}-rds-proxy-role" }
}

# Policy scoped to the single proxy_auth secret ARN only — not a wildcard (T-03-13).
resource "aws_iam_role_policy" "proxy" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${var.name_prefix}-rds-proxy-secrets"
  role  = aws_iam_role.proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.proxy_auth[0].arn]
    }]
  })
}

# Proxy SG uses SG-reference ingress — no CIDR on 5432; only the task SG may reach the
# proxy on PostgreSQL (T-03-14). Count = 0 by default so resource does not exist until
# enable_rds_proxy = true.
resource "aws_security_group" "proxy" {
  count       = var.enable_rds_proxy ? 1 : 0
  name_prefix = "${var.name_prefix}-rds-proxy-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from task SG to proxy"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.task_security_group_id] # NOT a CIDR — SG reference per Phase 1 pattern
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-rds-proxy-sg" }
}

resource "aws_db_proxy" "this" {
  count                  = var.enable_rds_proxy ? 1 : 0
  name                   = "${var.name_prefix}-rds-proxy"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.proxy[0].arn
  vpc_security_group_ids = [aws_security_group.proxy[0].id]
  vpc_subnet_ids         = var.subnet_ids

  auth {
    auth_scheme = "SECRETS"
    description = "RDS Proxy credentials from Secrets Manager"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.proxy_auth[0].arn
  }

  tags = { Name = "${var.name_prefix}-rds-proxy" }
}

# Terraform auto-imports this resource (does not create/destroy it) — required to
# configure the proxy connection pool. Count = 0 means it simply does not appear in
# the plan when enable_rds_proxy = false.
resource "aws_db_proxy_default_target_group" "this" {
  count         = var.enable_rds_proxy ? 1 : 0
  db_proxy_name = aws_db_proxy.this[0].name

  connection_pool_config {
    max_connections_percent      = 90 # 10% headroom reserved (T-03-15)
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120 # Prevents indefinite blocking (T-03-15)
  }
}

resource "aws_db_proxy_target" "this" {
  count                  = var.enable_rds_proxy ? 1 : 0
  db_proxy_name          = aws_db_proxy.this[0].name
  target_group_name      = aws_db_proxy_default_target_group.this[0].name
  db_instance_identifier = var.db_instance_identifier
}
