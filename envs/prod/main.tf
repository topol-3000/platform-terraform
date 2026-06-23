# Prod baseline — wires the shared-resource modules together.
#
# The networking module is implemented and wired below. The remaining module
# calls are commented out until each module is implemented, so that
# `terraform plan` succeeds on a fresh scaffold. Uncomment and fill inputs as
# you build each module, following SEED-001 build order.
#
# See: ../../../provisioner/.planning/seeds/SEED-001-aws-real-deployment.md

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# --- 2. Networking: VPC, public subnet (NO NAT gateway), security groups ------
module "networking" {
  source      = "../../modules/networking"
  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
}

# --- 3. Managed ECR repository (odoo-core image) --------------------------------
module "ecr" {
  source      = "../../modules/ecr"
  name_prefix = local.name_prefix
}

# --- 4. Shared ECS cluster (Fargate fleet) ------------------------------------
module "ecs" {
  source      = "../../modules/ecs"
  name_prefix = local.name_prefix
}

# --- 5. Databases -------------------------------------------------------------
# module "rds_tenant" {
#   source      = "../../modules/rds-tenant"
#   name_prefix = local.name_prefix
#   subnet_ids  = module.networking.private_subnet_ids
# }
#
# module "rds_proxy" {
#   source      = "../../modules/rds-proxy"
#   name_prefix = local.name_prefix
# }
#
# module "rds_control_plane" {
#   source      = "../../modules/rds-control-plane"
#   name_prefix = local.name_prefix
# }

# --- 6. Filestore, routing/TLS, secrets ---------------------------------------
# module "efs" {
#   source      = "../../modules/efs"
#   name_prefix = local.name_prefix
# }
#
# module "acm" {
#   source        = "../../modules/acm"
#   name_prefix   = local.name_prefix
#   tenant_domain = var.tenant_domain
# }
#
# module "alb" {
#   source         = "../../modules/alb"
#   name_prefix    = local.name_prefix
#   acm_cert_arn   = module.acm.cert_arn
# }
#
# module "route53" {
#   source        = "../../modules/route53"
#   tenant_domain = var.tenant_domain
# }
#
# module "ssm" {
#   source      = "../../modules/ssm"
#   name_prefix = local.name_prefix
# }
