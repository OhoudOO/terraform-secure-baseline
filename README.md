# Secure Terraform baseline (AWS)

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

## Checks

`scripts/check.sh` runs what CI runs, with Docker only: `terraform fmt`, `validate` for every root,
Trivy (blocks on HIGH/CRITICAL) and Checkov (blocks on any failure). Every Checkov skip in the code carries a reason.

Tested October 2026: all four roots validate with Terraform 1.16 and AWS provider 6.x; Trivy reports no HIGH or
CRITICAL issues; Checkov passes 134 checks with 0 failures and 23 documented skips. **Not yet applied to a real AWS
account**: run the first apply in a sandbox account and review the plan before using it for a client.
