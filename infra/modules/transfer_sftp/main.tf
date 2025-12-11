variable "project_name" {
  description = "Short project name used as prefix for AWS resources (e.g. bayflow-poc)"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to Transfer Family resources"
  type        = map(string)
}

variable "acme_ssh_public_key" {
  description = "SSH public key for the demo SFTP user (acme)"
  type        = string
}

variable "landing_bucket_arn" {
  description = "ARN of the landing S3 bucket"
  type        = string
}

variable "landing_bucket_name" {
  description = "Name of the landing S3 bucket"
  type        = string
}

####################
# IAM for Transfer logging
####################

resource "aws_iam_role" "transfer_logging_role" {
  name = "${var.project_name}-transfer-logging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Principal = { Service = "transfer.amazonaws.com" },
      Effect    = "Allow"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "transfer_logging_policy" {
  name = "${var.project_name}-transfer-logging-policy"
  role = aws_iam_role.transfer_logging_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      Resource = "*"
    }]
  })
}

####################
# AWS Transfer Family - SFTP Server & User
####################

resource "aws_transfer_server" "sftp" {
  identity_provider_type = "SERVICE_MANAGED"
  protocols              = ["SFTP"]
  endpoint_type          = "PUBLIC"
  logging_role           = aws_iam_role.transfer_logging_role.arn
  tags                   = var.tags
}

# IAM policy for S3 access restricted to landing bucket partners prefix
data "aws_iam_policy_document" "transfer_user_policy" {
  statement {
    sid       = "HomeDirList"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.landing_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["partners/*"]
    }
  }

  statement {
    sid       = "ObjectAccess"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.landing_bucket_arn}/partners/*"]
  }
}

data "aws_iam_policy_document" "transfer_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["transfer.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "transfer_user_role" {
  name               = "${var.project_name}-transfer-user-role"
  assume_role_policy = data.aws_iam_policy_document.transfer_trust.json
  tags               = var.tags
}

resource "aws_iam_policy" "transfer_user_access" {
  name   = "${var.project_name}-transfer-user-access"
  policy = data.aws_iam_policy_document.transfer_user_policy.json
}

resource "aws_iam_role_policy_attachment" "transfer_user_attach" {
  role       = aws_iam_role.transfer_user_role.name
  policy_arn = aws_iam_policy.transfer_user_access.arn
}

# Demo SFTP user (acme)
resource "aws_transfer_user" "acme" {
  server_id = aws_transfer_server.sftp.id
  user_name = "acme"
  role      = aws_iam_role.transfer_user_role.arn

  # PATH mode mapping directly to S3 bucket path
  home_directory_type = "PATH"
  home_directory      = "/${var.landing_bucket_name}/partners/acme/"

  tags = merge(var.tags, { Partner = "acme" })
}

resource "aws_transfer_ssh_key" "acme_key" {
  server_id = aws_transfer_server.sftp.id
  user_name = aws_transfer_user.acme.user_name
  body      = var.acme_ssh_public_key
}

# Seed a pseudo-folder for acme inbox
resource "aws_s3_object" "acme_inbox" {
  bucket  = var.landing_bucket_name
  key     = "partners/acme/inbox/"
  content = ""
}

output "transfer_server_id" {
  description = "ID of the AWS Transfer Family SFTP server"
  value       = aws_transfer_server.sftp.id
}
