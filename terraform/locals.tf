locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = "TechTemi/meridian-retail"
  }
}

locals {
  ecr_repositories = {
    auth     = "${var.ecr_repository_prefix}/auth"
    catalog  = "${var.ecr_repository_prefix}/catalog"
    orders   = "${var.ecr_repository_prefix}/orders"
    frontend = "${var.ecr_repository_prefix}/frontend"
  }
}
