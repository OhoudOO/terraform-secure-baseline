# Lets one GitHub repository deploy to this project without service account keys.
# Only workflow runs in the given repository AND GitHub environment can impersonate
# the deploy service account.
terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 7.0" }
  }
}

variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "github_repository" {
  type        = string
  description = "owner/repo, for example acme/platform."
}

variable "github_environment" {
  type = string
}

variable "project_roles" {
  type        = list(string)
  description = "Least-privilege roles for what the pipeline deploys. Never roles/owner or roles/editor."
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.name}-github"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  #checkov:skip=CKV_GCP_125:attribute_condition pins both the repository and the GitHub environment.
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
  }
  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.environment == '${var.github_environment}'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "deploy" {
  project      = var.project_id
  account_id   = "${var.name}-deploy"
  display_name = "GitHub deploy (${var.github_environment})"
}

resource "google_service_account_iam_member" "wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${var.github_environment}"
}

resource "google_project_iam_member" "deploy" {
  for_each = toset(var.project_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deploy.email}"
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  value = google_service_account.deploy.email
}
