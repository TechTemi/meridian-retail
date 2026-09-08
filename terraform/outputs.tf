output "deployment_context" {
  description = "Non-sensitive Terraform deployment context."

  value = {
    project_name = var.project_name
    environment  = var.environment
    aws_region   = var.aws_region
    name_prefix  = local.name_prefix
  }
}
