data "aws_caller_identity" "current" {}


locals {
  backup_bucket_name = "${var.project_name}-${var.environment}-backups-${data.aws_caller_identity.current.account_id}"
}


resource "aws_s3_bucket" "backups" {
  bucket        = local.backup_bucket_name
  force_destroy = false

  tags = {
    Name      = local.backup_bucket_name
    Purpose   = "PostgreSQLBackups"
    DataClass = "Backup"
  }
}


resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  depends_on = [
    aws_s3_bucket_versioning.backups
  ]

  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-postgresql-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
}
