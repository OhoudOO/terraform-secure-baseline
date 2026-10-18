# prod environment. State lives in the bootstrap bucket under prod/terraform.tfstate:
#   terraform init -backend-config=backend.hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    key          = "prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = var.project, Environment = "prod", ManagedBy = "terraform" }
  }
}

variable "project" {
  type = string
}

variable "region" {
  type    = string
  default = "me-south-1"
}

variable "github_repository" {
  type        = string
  description = "owner/repo allowed to deploy this environment."
}

variable "deploy_policy_arns" {
  type        = list(string)
  description = "Least-privilege policies for the deploy role."
}

variable "enable_account_baseline" {
  type        = bool
  default     = true
  description = "CloudTrail, GuardDuty and account guardrails. Keep true in one environment per AWS account only."
}

locals {
  name = "${var.project}-prod"
}

module "logging" {
  source = "../../modules/logging"
  name   = local.name
}

module "security_baseline" {
  count  = var.enable_account_baseline ? 1 : 0
  source = "../../modules/security-baseline"
  name   = local.name
}

module "network" {
  source             = "../../modules/network"
  name               = local.name
  cidr               = "10.30.0.0/16"
  single_nat_gateway = false
  kms_key_arn        = module.logging.kms_key_arn
}

module "github_oidc" {
  source             = "../../modules/github-oidc"
  name               = local.name
  github_repository  = var.github_repository
  github_environment = "prod"
  create_provider    = var.enable_account_baseline
  policy_arns        = var.deploy_policy_arns
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "deploy_role_arn" {
  value = module.github_oidc.role_arn
}
