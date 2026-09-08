variable "aws_region" {
  description = "AWS region used to deploy Meridian Retail infrastructure."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "project_name" {
  description = "Canonical project name used for resource naming and tagging."
  type        = string
  default     = "meridian-retail"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name may contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment represented by this Terraform root module."
  type        = string
  default     = "production"

  validation {
    condition = contains(
      [
        "development",
        "staging",
        "production"
      ],
      var.environment
    )

    error_message = "environment must be development, staging, or production."
  }
}
