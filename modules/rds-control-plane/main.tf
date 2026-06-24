# Module: rds-control-plane
# Purpose: Separate Multi-AZ PostgreSQL instance for provisioner control-plane data.
#
# SEED-001 note: MUST be separate from the tenant RDS. Never mix tenant + platform data.
#          multi_az = true (Multi-AZ for 99.9% SLA on provisioner operational data).

# Provisioner connects to the control-plane DB from ECS tasks (5432 from task SG, SG
# reference not CIDR — mirrors the tenant RDS pattern).
resource "aws_security_group" "cp_rds" {
  name_prefix = "${var.name_prefix}-cp-rds-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from task SG only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.task_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-cp-rds-sg" }
}

# Separate subnet group from the tenant RDS — no shared resources between tenant and
# control-plane (SEED-001 isolation).
resource "aws_db_subnet_group" "cp" {
  name        = "${var.name_prefix}-cp-rds"
  description = "Subnet group for the control-plane RDS instance."
  subnet_ids  = var.subnet_ids

  tags = { Name = "${var.name_prefix}-cp-rds-subnet-group" }
}

resource "aws_db_parameter_group" "cp" {
  name_prefix = "${var.name_prefix}-cp-pg16-"
  family      = "postgres16"
  description = "Parameter group for the control-plane PostgreSQL 16 instance."

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.name_prefix}-cp-pg16" }
}

# Control-plane data must never be accidentally destroyed — this is the provisioner's
# operational database. deletion_protection + final snapshot mirror the bootstrap S3 ethos.
# multi_az = true for 99.9% SLA.
resource "aws_db_instance" "control_plane" {
  identifier = "${var.name_prefix}-cp-rds"

  engine         = "postgres"
  engine_version = var.engine_version

  parameter_group_name = aws_db_parameter_group.cp.name
  instance_class       = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true # D-09: AWS-managed RDS key; no customer CMK this phase

  db_name  = "provisioner"
  username = "odoo_master"
  password = var.master_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.cp.name
  vpc_security_group_ids = [aws_security_group.cp_rds.id]

  publicly_accessible = false
  multi_az            = true # Multi-AZ for 99.9% SLA on provisioner operational data (D-07)

  deletion_protection       = true  # D-08
  skip_final_snapshot       = false # D-08
  final_snapshot_identifier = "${var.name_prefix}-cp-rds-final"

  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  tags = { Name = "${var.name_prefix}-cp-rds" }

  lifecycle {
    ignore_changes = [password] # D-02: allow out-of-band rotation without Terraform drift
  }
}
