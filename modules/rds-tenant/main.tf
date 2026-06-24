# Module: rds-tenant
# Purpose: Shared Single-AZ PostgreSQL instance, DB subnet group, and RDS security group.
#          The provisioner adapter creates per-tenant databases and roles at runtime; this
#          module owns only the shared instance and network resources.
#
# SEED-001 note: Single-AZ at MVP (cost). Size on max_connections (~5-20 conns/tenant).
#          multi_az = false here; see rds-control-plane for the Multi-AZ control-plane instance.

# Only ECS tasks may reach PostgreSQL on 5432 (SG reference, not CIDR — mirrors the networking module task SG pattern).
resource "aws_security_group" "rds_tenant" {
  name_prefix = "${var.name_prefix}-rds-tenant-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from task SG only"
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

  tags = { Name = "${var.name_prefix}-rds-tenant-sg" }
}

resource "aws_db_subnet_group" "tenant" {
  name        = "${var.name_prefix}-tenant-rds"
  description = "Subnet group for the shared tenant RDS instance."
  subnet_ids  = var.subnet_ids

  tags = { Name = "${var.name_prefix}-tenant-rds-subnet-group" }
}

# family=postgres16 required for engine_version=16; create_before_destroy avoids name conflict on replacement.
resource "aws_db_parameter_group" "tenant" {
  name_prefix = "${var.name_prefix}-tenant-pg16-"
  family      = "postgres16"
  description = "Parameter group for the shared tenant PostgreSQL 16 instance."

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.name_prefix}-tenant-pg16" }
}

# Tenant data lives here — deletion_protection + final snapshot guard against accidental destroy (bootstrap S3 ethos). lifecycle.ignore_changes = [password] allows out-of-band password rotation.
resource "aws_db_instance" "tenant" {
  identifier = "${var.name_prefix}-tenant-rds"

  engine               = "postgres"
  engine_version       = var.engine_version
  parameter_group_name = aws_db_parameter_group.tenant.name

  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true # D-09: AWS-managed RDS key; no customer-managed CMK this phase

  db_name  = "odoo_shared"
  username = "odoo_master"
  password = var.master_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.tenant.name
  vpc_security_group_ids = [aws_security_group.rds_tenant.id]

  publicly_accessible = false

  multi_az = false # D-07: Single-AZ for tenant MVP cost per SEED-001

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-tenant-rds-final" # D-08

  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  tags = { Name = "${var.name_prefix}-tenant-rds" }

  lifecycle {
    ignore_changes = [password] # D-02: allow out-of-band rotation without Terraform drift
  }
}
