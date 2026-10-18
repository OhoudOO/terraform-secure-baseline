# Lets one GitHub repository deploy to this account without stored keys.
# The role can only be assumed from the given repository AND GitHub environment,
# so a pull request from a branch cannot reach production.
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

variable "name" {
  type = string
}

variable "github_repository" {
  type        = string
  description = "owner/repo, for example acme/platform."
}

variable "github_environment" {
  type        = string
  description = "GitHub environment allowed to assume the role, for example production."
}

variable "create_provider" {
  type        = bool
  default     = true
  description = "The GitHub OIDC provider exists once per account; set false if it already exists."
}

variable "policy_arns" {
  type        = list(string)
  description = "Least-privilege policies for what the pipeline deploys. Never AdministratorAccess."
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  provider_arn = var.create_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name}-github-${var.github_environment}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.deploy.name
  policy_arn = each.value
}

output "role_arn" {
  value = aws_iam_role.deploy.arn
}
