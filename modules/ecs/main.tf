# Module: ecs
# Purpose: Shared ECS/Fargate cluster for the tenant fleet. The provisioner creates
#          per-tenant task definitions and services at runtime; the cluster and its
#          capacity-provider wiring belong in the shared baseline.
#
# SEED-001 note: Fargate launch type at MVP; evolve to an EC2 capacity provider for
# density later — no AwsDeploymentAdapter rewrite required, only cluster changes.

# Shared ECS cluster — all tenant Fargate tasks schedule onto this one control plane.
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  # "enabled" (not "enhanced") keeps CloudWatch metrics/logs for audit and incident
  # response without the extra cost of Container Insights Enhanced (T-02-05 mitigated).
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.name_prefix}-cluster" }
}

# Wire FARGATE and FARGATE_SPOT capacity providers to the cluster.
# FARGATE_SPOT enables cost-optimised scheduling for interruptible tenant workloads;
# FARGATE is the safe baseline for workloads that cannot tolerate interruption.
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Default to FARGATE so new services land on on-demand capacity unless the
  # provisioner explicitly requests FARGATE_SPOT.
  default_capacity_provider_strategy {
    # FARGATE as the primary provider — guaranteed capacity, no interruption risk.
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  default_capacity_provider_strategy {
    # FARGATE_SPOT as secondary — cost savings for tasks that tolerate preemption.
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }
}
