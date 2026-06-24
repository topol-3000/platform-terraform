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

# --- 5. Databases and secrets -------------------------------------------------

# SSM must come first — rds modules consume its sensitive password outputs.
module "ssm" {
  source      = "../../modules/ssm"
  name_prefix = local.name_prefix
}

# Shared Single-AZ PostgreSQL for tenant databases (one database per tenant, created by the adapter).
module "rds_tenant" {
  source                 = "../../modules/rds-tenant"
  name_prefix            = local.name_prefix
  subnet_ids             = module.networking.private_subnet_ids
  vpc_id                 = module.networking.vpc_id
  task_security_group_id = module.networking.task_security_group_id
  master_password        = module.ssm.tenant_rds_password
  instance_class         = var.rds_instance_class
  engine_version         = var.rds_engine_version
  allocated_storage      = var.rds_allocated_storage
  max_allocated_storage  = var.rds_max_allocated_storage
}

# RDS Proxy — gated behind var.enable_rds_proxy (default false; activate at ~30 tenants).
module "rds_proxy" {
  source                 = "../../modules/rds-proxy"
  name_prefix            = local.name_prefix
  enable_rds_proxy       = var.enable_rds_proxy
  db_instance_identifier = module.rds_tenant.identifier
  subnet_ids             = module.networking.private_subnet_ids
  vpc_id                 = module.networking.vpc_id
  task_security_group_id = module.networking.task_security_group_id
  master_username        = "odoo_master"
  master_password        = module.ssm.tenant_rds_password
}

# Separate Multi-AZ PostgreSQL for the control-plane (provisioner) database — isolated from tenant data.
module "rds_control_plane" {
  source                 = "../../modules/rds-control-plane"
  name_prefix            = local.name_prefix
  subnet_ids             = module.networking.private_subnet_ids
  vpc_id                 = module.networking.vpc_id
  task_security_group_id = module.networking.task_security_group_id
  master_password        = module.ssm.cp_rds_password
  instance_class         = var.rds_instance_class
  engine_version         = var.rds_engine_version
  allocated_storage      = var.rds_allocated_storage
  max_allocated_storage  = var.rds_max_allocated_storage
}

# --- 6. Filestore, routing/TLS ------------------------------------------------
module "efs" {
  source                 = "../../modules/efs"
  name_prefix            = local.name_prefix
  vpc_id                 = module.networking.vpc_id
  task_security_group_id = module.networking.task_security_group_id
  subnet_ids_by_az       = module.networking.private_subnets_by_az
}

# Build step 6 — Routing/TLS. acm MUST appear before alb (module.acm.cert_arn dependency).
module "acm" {
  source        = "../../modules/acm"
  name_prefix   = local.name_prefix
  tenant_domain = var.tenant_domain
}

module "alb" {
  source            = "../../modules/alb"
  name_prefix       = local.name_prefix
  acm_cert_arn      = module.acm.cert_arn
  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.networking.alb_security_group_id
}

module "route53" {
  source        = "../../modules/route53"
  name_prefix   = local.name_prefix
  tenant_domain = var.tenant_domain
}
