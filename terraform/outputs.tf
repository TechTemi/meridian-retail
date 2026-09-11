output "deployment_context" {
  description = "Non-sensitive Terraform deployment context."

  value = {
    project_name = var.project_name
    environment  = var.environment
    aws_region   = var.aws_region
    name_prefix  = local.name_prefix
  }
}

output "vpc_id" {
  description = "ID of the Meridian Retail VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block assigned to the Meridian Retail VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the Meridian public application subnet."
  value       = aws_subnet.public.id
}

output "public_subnet_cidr" {
  description = "CIDR block assigned to the Meridian public application subnet."
  value       = aws_subnet.public.cidr_block
}

output "public_subnet_availability_zone" {
  description = "Availability Zone containing the Meridian public subnet."
  value       = aws_subnet.public.availability_zone
}

output "internet_gateway_id" {
  description = "ID of the Meridian Internet Gateway."
  value       = aws_internet_gateway.main.id
}

output "public_route_table_id" {
  description = "ID of the route table explicitly associated with the public subnet."
  value       = aws_route_table.public.id
}

output "application_security_group_id" {
  description = "ID of the security group protecting the Meridian application host."
  value       = aws_security_group.application.id
}

output "ecr_repository_urls" {
  description = "Private ECR repository URLs for Meridian application services."

  value = {
    for service, repository in aws_ecr_repository.service :
    service => repository.repository_url
  }
}

output "ecr_repository_arns" {
  description = "ARNs of the private Meridian ECR repositories."

  value = {
    for service, repository in aws_ecr_repository.service :
    service => repository.arn
  }
}

output "backup_bucket_name" {
  description = "Name of the private S3 bucket used for Meridian PostgreSQL backups."
  value       = aws_s3_bucket.backups.bucket
}

output "backup_bucket_arn" {
  description = "ARN of the private S3 bucket used for Meridian PostgreSQL backups."
  value       = aws_s3_bucket.backups.arn
}

output "application_iam_role_name" {
  description = "Name of the least-privilege IAM role used by the Meridian EC2 host."
  value       = aws_iam_role.application.name
}

output "application_iam_role_arn" {
  description = "ARN of the least-privilege IAM role used by the Meridian EC2 host."
  value       = aws_iam_role.application.arn
}

output "application_instance_profile_name" {
  description = "Name of the EC2 instance profile used by the Meridian application host."
  value       = aws_iam_instance_profile.application.name
}

output "github_deploy_role_name" {
  description = "Name of the GitHub Actions OIDC deployment role."
  value       = aws_iam_role.github_deploy.name
}

output "github_deploy_role_arn" {
  description = "ARN of the GitHub Actions OIDC deployment role."
  value       = aws_iam_role.github_deploy.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the account-level GitHub Actions OIDC provider."
  value       = local.github_oidc_provider_arn
}
