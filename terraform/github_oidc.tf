locals {
  github_oidc_url      = "https://token.actions.githubusercontent.com"
  github_oidc_host     = "token.actions.githubusercontent.com"
  github_oidc_audience = "sts.amazonaws.com"

  github_oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.github_oidc_host}"

  github_oidc_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:ref:refs/heads/main"

  github_security_group_resource_arn = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/*"
}


data "aws_iam_openid_connect_provider" "github_existing" {
  count = var.create_github_oidc_provider ? 0 : 1

  arn = local.github_oidc_provider_arn
}


resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url = local.github_oidc_url

  client_id_list = [
    local.github_oidc_audience
  ]

  tags = {
    Name    = "${local.name_prefix}-github-oidc"
    Purpose = "GitHubActionsFederation"
  }
}


data "aws_iam_policy_document" "github_deploy_assume_role" {
  statement {
    sid     = "AllowGitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        local.github_oidc_provider_arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"

      values = [
        local.github_oidc_audience
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"

      values = [
        local.github_oidc_subject
      ]
    }
  }
}


resource "aws_iam_role" "github_deploy" {
  name        = "${local.name_prefix}-github-deploy-role"
  description = "OIDC-federated deployment role for Meridian GitHub Actions on main."

  assume_role_policy   = data.aws_iam_policy_document.github_deploy_assume_role.json
  max_session_duration = 3600

  depends_on = [
    aws_iam_openid_connect_provider.github,
    data.aws_iam_openid_connect_provider.github_existing
  ]

  tags = {
    Name = "${local.name_prefix}-github-deploy-role"
  }
}


data "aws_iam_policy_document" "github_deploy_permissions" {
  statement {
    sid       = "AllowECRAuthentication"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowMeridianECRPush"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = values(local.ecr_repository_arns)
  }

  statement {
    sid       = "AllowSecurityGroupDiscovery"
    effect    = "Allow"
    actions   = ["ec2:DescribeSecurityGroups"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowTemporarySshIngressMutation"
    effect = "Allow"

    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress"
    ]

    resources = [
      local.github_security_group_resource_arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Name"
      values   = ["${local.name_prefix}-app-sg"]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:Region"
      values   = [var.aws_region]
    }
  }
}


resource "aws_iam_role_policy" "github_deploy" {
  name = "${local.name_prefix}-github-deploy-policy"
  role = aws_iam_role.github_deploy.id

  policy = data.aws_iam_policy_document.github_deploy_permissions.json
}
