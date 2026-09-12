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

output "application_instance_id" {
  description = "ID of the Meridian Ubuntu application EC2 instance."
  value       = aws_instance.application.id
}

output "application_private_ip" {
  description = "Private IPv4 address of the Meridian application EC2 instance."
  value       = aws_instance.application.private_ip
}

output "application_ami_id" {
  description = "Canonical Ubuntu 22.04 AMI used by the Meridian application host."
  value       = nonsensitive(data.aws_ssm_parameter.ubuntu_2204_ami.value)
}

output "application_instance_type" {
  description = "EC2 instance type used by the Meridian application host."
  value       = aws_instance.application.instance_type
}

output "application_ssh_key_name" {
  description = "Name of the EC2 key pair used for Meridian administrator SSH."
  value       = aws_key_pair.application.key_name
}

output "application_public_ip" {
  description = "Stable Elastic IPv4 address assigned to the Meridian application host."
  value       = aws_eip.application.public_ip
}

output "application_eip_allocation_id" {
  description = "Allocation ID of the Meridian application Elastic IP."
  value       = aws_eip.application.allocation_id
}
