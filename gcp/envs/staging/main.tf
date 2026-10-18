# staging environment on GCP: one project per environment is recommended.
#   terraform init -backend-config=backend.hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 7.0" }
  }
  backend "gcs" {
    prefix = "staging"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  default_labels = {
    environment = "staging"
    managed-by  = "terraform"
  }
}

variable "project_id" {
  type = string
}

variable "name" {
  type        = string
  description = "Short prefix, 4 to 20 lowercase letters and dashes, for example acme."
}

variable "region" {
  type    = string
  default = "me-central2"
}

variable "github_repository" {
  type = string
}

variable "deploy_project_roles" {
  type        = list(string)
  description = "Least-privilege roles for the deploy service account."
}

variable "enable_guardrails" {
  type        = bool
  default     = true
  description = "Project organization policies. Needs the project inside an organization."
}

locals {
  name = "${var.name}-staging"
}

module "logging" {
  source     = "../../modules/logging"
  project_id = var.project_id
  name       = local.name
  region     = var.region
}

module "guardrails" {
  count      = var.enable_guardrails ? 1 : 0
  source     = "../../modules/guardrails"
  project_id = var.project_id
}

module "network" {
  source     = "../../modules/network"
  project_id = var.project_id
  name       = local.name
  region     = var.region
  cidr       = "10.20.0.0/20"
}

module "github_wif" {
  source             = "../../modules/github-wif"
  project_id         = var.project_id
  name               = local.name
  github_repository  = var.github_repository
  github_environment = "staging"
  project_roles      = var.deploy_project_roles
}

output "workload_identity_provider" {
  value = module.github_wif.workload_identity_provider
}

output "deploy_service_account" {
  value = module.github_wif.service_account_email
}
