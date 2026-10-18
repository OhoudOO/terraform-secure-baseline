# One-time setup per GCP project that holds Terraform state: a KMS-encrypted,
# versioned bucket with public access prevention and uniform access.
terraform {
  required_version = ">= 1.10"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 7.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type        = string
  description = "Project that holds Terraform state (often a separate admin project)."
}

variable "region" {
  type    = string
  default = "me-central2"
}

data "google_project" "this" {}

resource "google_kms_key_ring" "state" {
  name     = "terraform-state"
  location = var.region
}

resource "google_kms_crypto_key" "state" {
  name            = "terraform-state"
  key_ring        = google_kms_key_ring.state.id
  rotation_period = "7776000s"
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "storage" {
  crypto_key_id = google_kms_crypto_key.state.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_storage_bucket" "state" {
  #checkov:skip=CKV_GCP_62:Access logs for the state bucket are covered by Cloud Audit Logs data access logging when enabled.
  name                        = "${var.project_id}-tfstate"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  versioning { enabled = true }
  encryption { default_kms_key_name = google_kms_crypto_key.state.id }
  lifecycle_rule {
    condition {
      num_newer_versions = 20
      with_state         = "ARCHIVED"
    }
    action { type = "Delete" }
  }
  depends_on = [google_kms_crypto_key_iam_member.storage]
}

output "state_bucket" {
  value = google_storage_bucket.state.name
}
