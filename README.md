# Secure Terraform baseline (AWS and GCP)

Starting point for the "Secure IaC & Cloud Engineering" service: an AWS account baseline and
one network per environment, deployed from GitHub without stored keys.

| Folder | What it creates |
| --- | --- |
| `bootstrap/` | KMS-encrypted, versioned, TLS-only S3 bucket for Terraform state (run once per account) |
| `modules/logging` | KMS key, encrypted audit log bucket, multi-region CloudTrail with log file validation |
| `modules/security-baseline` | S3 account public access block, EBS encryption by default, IAM password policy, GuardDuty, IAM Access Analyzer |
| `modules/network` | VPC, public/private subnets over 2 AZs, NAT, deny-all default security group, encrypted VPC flow logs |
| `modules/github-oidc` | GitHub OIDC provider and a deploy role limited to one repository and one GitHub environment |
| `envs/dev`, `envs/staging`, `envs/prod` | The modules wired per environment (prod: one NAT gateway per AZ) |

## Use for a client

1. Copy this repository into the client's organisation (private).
2. `bootstrap/`: `terraform init && terraform apply -var project=acme` with an admin session, once per AWS account.
3. Per environment: copy `backend.hcl.example` and `terraform.tfvars.example`, then `terraform init -backend-config=backend.hcl` and `terraform plan`.
   Recommended: one AWS account per environment. If several environments share an account, set
   `enable_account_baseline = false` in all but one of them.
4. Write a least-privilege policy for what the pipeline deploys and pass it as `deploy_policy_arns`. Never AdministratorAccess.
5. GitHub: create environments `dev`, `staging`, `prod` (required reviewers on staging and prod), add the
   repository variables used in `.github/workflows/terraform.yml`, then set `DEPLOY_ENABLED=true`.

## GCP (`gcp/`)

Same structure for Google Cloud, one project per environment, default region `me-central2` (Dammam):

| Folder | What it creates |
| --- | --- |
| `gcp/bootstrap/` | CMEK-encrypted, versioned state bucket with public access prevention |
| `gcp/modules/logging` | Admin and data access audit logs, exported by a log sink to a CMEK bucket with a retention policy (`lock_retention` makes it permanent) |
| `gcp/modules/guardrails` | Project organization policies: no service account keys, no public buckets, uniform bucket access, OS Login, no default network, no VM external IPs, no public Cloud SQL (needs the project inside an organization) |
| `gcp/modules/network` | Custom VPC, private subnet with Private Google Access and flow logs, Cloud NAT, explicit deny-all ingress |
| `gcp/modules/github-wif` | Workload Identity Federation limited to one repository and one GitHub environment, and a deploy service account with the roles you pass |

Deploys run from `.github/workflows/terraform-gcp.yml` once the repository variable `DEPLOY_ENABLED_GCP` is true.

## Checks

`scripts/check.sh` runs what CI runs, with Docker only: `terraform fmt`, `validate` for every root,
Trivy (blocks on HIGH/CRITICAL) and Checkov (blocks on any failure). Every Checkov skip in the code carries a reason.

Tested October 2026: all eight roots (AWS and GCP) validate with Terraform 1.16, AWS provider 6.x and Google provider 7.x; Trivy reports no HIGH or
CRITICAL issues; Checkov passes 165 checks with 0 failures and 31 documented skips. **Not yet applied to a real AWS account or
GCP project**: run the first apply in a sandbox and review the plan before using it for a client.
