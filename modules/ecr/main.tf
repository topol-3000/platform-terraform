# Module: ecr
# Purpose: Managed AWS ECR repository for the odoo-core image (CI/CD pushes; AWS-native private storage).
#
# SEED-001 note: The original architecture referenced an upstream registry mirror approach;
# D-01 supersedes that in favour of a managed repository. A managed repo needs no upstream
# registry credential (avoids a Secrets Manager exception to the SSM-only secret rule), and
# its repository_url is a resource attribute — image_uri resolves with no STS lookup and no
# account_id variable, keeping the offline make plan-check gate intact.

# Private ECR repository for the odoo-core image — CI/CD pushes the built image here;
# ECS tasks pull from this repository at runtime.
resource "aws_ecr_repository" "odoo_core" {
  name = "${var.name_prefix}-odoo-core"

  # IMMUTABLE: release tags cannot be silently overwritten — a new push must use a new tag.
  # Prevents a compromised CI pipeline from replacing a deployed image without changing its tag.
  image_tag_mutability = "IMMUTABLE"

  # Catch CVEs at push time rather than at deploy time.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encrypt image layers at rest with AES256. KMS CMK deferred — low marginal value at MVP
  # because ECR is already private and access-controlled via IAM.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.name_prefix}-odoo-core" }
}

# Expire untagged images to prevent registry bloat and unbounded storage cost.
# CI/CD produces untagged intermediate layers on every build; without this rule the
# registry grows without bound.
resource "aws_ecr_lifecycle_policy" "odoo_core" {
  repository = aws_ecr_repository.odoo_core.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
