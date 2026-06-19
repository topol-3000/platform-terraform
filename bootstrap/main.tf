# Creates the S3 bucket that stores Terraform remote state for every other
# config in this repo. Locking is done with S3 native lockfiles
# (use_lockfile = true on the backend), so NO DynamoDB table is needed.

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # State is the source of truth for live infrastructure — guard against an
  # accidental `terraform destroy` of the bootstrap itself.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning lets you recover a previous state if a state write goes wrong.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest (state can contain secrets, e.g. RDS passwords).
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# State must never be public.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire old state versions so the bucket doesn't grow unbounded.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    # Clean up incomplete multipart uploads from interrupted state writes.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
