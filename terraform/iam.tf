data "aws_partition" "current" {}


locals {
  ecr_repository_arns = {
    for service, repository_name in local.ecr_repositories :
    service => "arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${repository_name}"
  }

  backup_bucket_iam_arn = "arn:${data.aws_partition.current.partition}:s3:::${local.backup_bucket_name}"
}


data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "AllowEC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "application" {
  name        = "${local.name_prefix}-ec2-role"
  description = "Least-privilege IAM role for the Meridian application EC2 host."

  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${local.name_prefix}-ec2-role"
  }
}


data "aws_iam_policy_document" "application_permissions" {
  statement {
    sid       = "AllowECRAuthentication"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowMeridianECRPull"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]

    resources = values(local.ecr_repository_arns)
  }

  statement {
    sid    = "AllowBackupBucketListing"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]

    resources = [
      local.backup_bucket_iam_arn
    ]
  }

  statement {
    sid    = "AllowBackupObjectReadWrite"
    effect = "Allow"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]

    resources = [
      "${local.backup_bucket_iam_arn}/*"
    ]
  }
}


resource "aws_iam_role_policy" "application" {
  name = "${local.name_prefix}-ec2-policy"
  role = aws_iam_role.application.id

  policy = data.aws_iam_policy_document.application_permissions.json
}


resource "aws_iam_instance_profile" "application" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.application.name

  tags = {
    Name = "${local.name_prefix}-ec2-profile"
  }
}
