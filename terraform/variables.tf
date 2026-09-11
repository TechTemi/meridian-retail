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

variable "ecr_repository_prefix" {
  description = "Prefix used for Meridian private ECR repository names."
  type        = string
  default     = "meridian"

  validation {
    condition = can(
      regex(
        "^[a-z0-9]+(?:[._/-][a-z0-9]+)*$",
        var.ecr_repository_prefix
      )
    )

    error_message = "ecr_repository_prefix must use lowercase ECR-compatible repository-name characters."
  }
}

variable "github_owner" {
  description = "GitHub repository owner authorized to deploy Meridian."
  type        = string
  default     = "TechTemi"
}

variable "github_repository" {
  description = "GitHub repository authorized to deploy Meridian."
  type        = string
  default     = "meridian-retail"
}

variable "github_owner_id" {
  description = "Immutable numeric GitHub owner ID used in the OIDC subject."
  type        = string
  default     = "122737846"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be a numeric GitHub owner ID."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID used in the OIDC subject."
  type        = string
  default     = "1360367413"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be a numeric GitHub repository ID."
  }
}

variable "create_github_oidc_provider" {
  description = "Whether this Terraform root module should create the account-level GitHub Actions OIDC provider."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "EC2 instance type used by the Meridian application host."
  type        = string
  default     = "t3.small"

  validation {
    condition     = length(trimspace(var.instance_type)) > 0
    error_message = "instance_type must not be empty."
  }
}

variable "ec2_ssh_public_key" {
  description = "OpenSSH public key imported into EC2 for Meridian administrator access."
  type        = string

  validation {
    condition = can(
      regex(
        "^ssh-(rsa|ed25519)[[:space:]]+",
        trimspace(var.ec2_ssh_public_key)
      )
    )

    error_message = "ec2_ssh_public_key must be a valid RSA or ED25519 OpenSSH public key."
  }
}
