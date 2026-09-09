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
