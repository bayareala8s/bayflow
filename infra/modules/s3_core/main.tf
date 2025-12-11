####################
# S3 Core (landing, target, config)
####################

variable "project_name" {
  type        = string
  description = "Project name used as prefix for S3 buckets"
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
}

####################
# S3 Buckets
####################

resource "aws_s3_bucket" "landing" {
  bucket = "${var.project_name}-landing"
  tags   = var.tags
}

resource "aws_s3_bucket" "target" {
  bucket = "${var.project_name}-target"
  tags   = var.tags
}

resource "aws_s3_bucket" "config" {
  bucket = "${var.project_name}-config"
  tags   = var.tags
}

resource "aws_s3_bucket_notification" "landing_eventbridge" {
  bucket = aws_s3_bucket.landing.id

  eventbridge = true
}

resource "aws_s3_bucket_public_access_block" "pab" {
  for_each = {
    landing = aws_s3_bucket.landing.id
    target  = aws_s3_bucket.target.id
    config  = aws_s3_bucket.config.id
  }

  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  for_each = {
    landing = aws_s3_bucket.landing.id
    target  = aws_s3_bucket.target.id
    config  = aws_s3_bucket.config.id
  }

  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

####################
# Outputs
####################

output "landing_bucket_name" {
  description = "Name of the landing S3 bucket"
  value       = aws_s3_bucket.landing.bucket
}

output "landing_bucket_arn" {
  description = "ARN of the landing S3 bucket"
  value       = aws_s3_bucket.landing.arn
}

output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target.bucket
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target.arn
}

output "config_bucket_name" {
  description = "Name of the config S3 bucket"
  value       = aws_s3_bucket.config.bucket
}

output "config_bucket_arn" {
  description = "ARN of the config S3 bucket"
  value       = aws_s3_bucket.config.arn
}
