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

variable "vpc_cidr" {
  description = "IPv4 CIDR block assigned to the Meridian Retail VPC."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR block assigned to the Meridian public application subnet."
  type        = string
  default     = "10.40.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone" {
  description = "Availability Zone used for the Meridian single-node production deployment."
  type        = string
  default     = "us-east-1a"

  validation {
    condition     = startswith(var.availability_zone, var.aws_region)
    error_message = "availability_zone must belong to the configured aws_region."
  }
}

variable "admin_cidr" {
  description = "Single administrator public IPv4 address permitted to access SSH."
  type        = string

  validation {
    condition = (
      can(cidrnetmask(var.admin_cidr)) &&
      can(regex("/32$", var.admin_cidr))
    )

    error_message = "admin_cidr must be a valid single IPv4 address expressed as a /32 CIDR."
  }
}
