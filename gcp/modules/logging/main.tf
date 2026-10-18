# Audit trail: admin and data access audit logs for the project, exported by a log sink
# to a KMS-encrypted bucket with a retention policy (lock it only once the client agrees).
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

variable "region" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 365
}

variable "lock_retention" {
  type        = bool
  default     = false
  description = "Locking cannot be undone: logs can then never be deleted before retention ends."
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_project_iam_audit_config" "all" {
  project = var.project_id
  service = "allServices"
  audit_log_config { log_type = "ADMIN_READ" }
  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
}

resource "google_kms_key_ring" "logs" {
  project  = var.project_id
  name     = "${var.name}-logs"
  location = var.region
}

resource "google_kms_crypto_key" "logs" {
  name            = "${var.name}-logs"
  key_ring        = google_kms_key_ring.logs.id
  rotation_period = "7776000s"
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "storage" {
  crypto_key_id = google_kms_crypto_key.logs.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_storage_bucket" "audit" {
  #checkov:skip=CKV_GCP_62:Logging the audit bucket into itself would loop; use a separate bucket if the client requires it.
  project                     = var.project_id
  name                        = "${var.project_id}-audit-logs"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning { enabled = true }
  encryption { default_kms_key_name = google_kms_crypto_key.logs.id }
  retention_policy {
    retention_period = var.retention_days * 86400
    is_locked        = var.lock_retention
  }
  depends_on = [google_kms_crypto_key_iam_member.storage]
}

resource "google_logging_project_sink" "audit" {
  #checkov:skip=CKV2_GCP_4:Bucket Lock cannot be undone; set lock_retention = true once the client agrees.
  project                = var.project_id
  name                   = "${var.name}-audit-to-bucket"
  destination            = "storage.googleapis.com/${google_storage_bucket.audit.name}"
  filter                 = "logName:\"cloudaudit.googleapis.com\""
  unique_writer_identity = true
}

resource "google_storage_bucket_iam_member" "sink_writer" {
  bucket = google_storage_bucket.audit.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit.writer_identity
}

output "audit_bucket" {
  value = google_storage_bucket.audit.name
}
