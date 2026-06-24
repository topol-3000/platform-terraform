# Module: efs
# Purpose: Shared EFS filesystem (per-tenant access points created by the adapter)
#
# SEED-001 note: Mounted at /var/lib/odoo, durable across task replacement / cross-AZ reschedule (NOT EBS). Watch small-file latency under /sessions.
#
# STATUS: implemented.
# See ../../../provisioner/.planning/seeds/SEED-001-aws-real-deployment.md

# Only ECS tasks may reach EFS on NFS port 2049 (SG reference, not CIDR — mirrors the networking and RDS SG patterns).
resource "aws_security_group" "efs" {
  name_prefix = "${var.name_prefix}-efs-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from task SG only"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.task_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-efs-sg" }
}

# Shared encrypted EFS filesystem — durable Odoo filestore/session data across task replacement. IA tiering after 30 days idle; return-on-access prevents latency penalty for hot files (SEED-001 /sessions warning, D-01).
resource "aws_efs_file_system" "main" {
  creation_token   = "${var.name_prefix}-efs"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = { Name = "${var.name_prefix}-efs" }
}

# One mount target per AZ (for_each over AZ map ensures no duplicate-AZ apply failure — D-04).
resource "aws_efs_mount_target" "main" {
  for_each = var.subnet_ids_by_az

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}
