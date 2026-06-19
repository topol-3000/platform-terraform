# Module: networking
# Purpose: VPC, public subnets (NO NAT gateway), internet gateway, route table, and security groups
#
# SEED-001 note: Public subnets only, no NAT (cost). Tenant task SG must accept 8069 ONLY
# from the ALB SG id — the sole guard against direct internet exposure of tasks on public subnets.

# VPC for the prod baseline — all shared resources live in this network boundary.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # ECS tasks need DNS to resolve AWS endpoints (ECR, SSM, etc.)
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# One public subnet per AZ — no NAT, so tasks need public IPs for egress (no private subnets).
resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index) # /16 -> /20 per subnet
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # No NAT -> tasks need public IPs for outbound traffic

  tags = { Name = "${var.name_prefix}-public-${var.azs[count.index]}" }
}

# Internet gateway — the single exit point for all public-subnet traffic.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.name_prefix}-igw" }
}

# Public route table with default route to the IGW — enables public-subnet egress.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.name_prefix}-public-rt" }
}

# Associate every public subnet with the public route table so egress works.
resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ALB security group — accepts public HTTP/HTTPS traffic and allows all outbound to reach targets.
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-alb-sg" }
}

# Task security group — only the ALB may reach Odoo on 8069 (SG reference, not CIDR — D-09).
# Tasks are on public subnets; this SG is the sole guard against direct internet exposure.
resource "aws_security_group" "task" {
  name_prefix = "${var.name_prefix}-task-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Odoo port from ALB only"
    from_port       = 8069
    to_port         = 8069
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # NOT a CIDR — prevents direct internet access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow-all egress: tasks pull images from ECR, reach SSM, etc.
  }

  tags = { Name = "${var.name_prefix}-task-sg" }
}
