# Project-level organization policies. They need the project to be inside a GCP
# organization and the deployer to hold roles/orgpolicy.policyAdmin.
terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 7.0" }
  }
}

variable "project_id" {
  type = string
}

locals {
  enforced = toset([
    "iam.disableServiceAccountKeyCreation", # no long-lived service account keys
    "storage.publicAccessPrevention",       # no public buckets
    "storage.uniformBucketLevelAccess",     # IAM only, no per-object ACLs
    "compute.requireOsLogin",               # SSH through IAM, not project-wide keys
    "compute.skipDefaultNetworkCreation",   # no default network with open firewall rules
    "sql.restrictPublicIp",                 # no public IP on Cloud SQL
  ])
}

resource "google_org_policy_policy" "enforced" {
  for_each = local.enforced
  name     = "projects/${var.project_id}/policies/${each.value}"
  parent   = "projects/${var.project_id}"
  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "no_vm_external_ip" {
  name   = "projects/${var.project_id}/policies/compute.vmExternalIpAccess"
  parent = "projects/${var.project_id}"
  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}
