
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

####################
# Variables
####################

variable "project_name" {
  description = "Short project name used as prefix for AWS resources (e.g. bayflow-poc)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "alerts_email" {
  description = "Email address for SNS alerts"
  type        = string
}

variable "acme_ssh_public_key" {
  description = "SSH public key for the demo SFTP user (acme)"
  type        = string
}

####################
# Locals & Tags
####################

locals {
  project = var.project_name
  tags = {
    Project = local.project
    Owner   = "BayAreaLa8s"
    Env     = "poc"
  }
}

####################
# S3 Buckets (s3_core module)
####################

module "s3_core" {
  source = "./modules/s3_core"

  project_name = local.project
  tags         = local.tags
}

####################
# CloudWatch & SNS (alerts module)
####################

module "sns_alerts" {
  source = "./modules/sns_alerts"

  project_name = local.project
  tags         = local.tags
  alerts_email = var.alerts_email
}

####################
# DynamoDB - Job Tracking (module)
####################

module "dynamodb_jobs" {
  source = "./modules/dynamodb_jobs"

  project_name = local.project
  tags         = local.tags
}

####################
# AWS Transfer Family - SFTP Server & User (module)
####################

module "transfer_sftp" {
  source = "./modules/transfer_sftp"

  project_name        = local.project
  tags                = local.tags
  acme_ssh_public_key = var.acme_ssh_public_key

  landing_bucket_arn  = module.s3_core.landing_bucket_arn
  landing_bucket_name = module.s3_core.landing_bucket_name
}

####################
# Lambda Function (mover)
####################

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/mover/app.py"
  output_path = "${path.module}/lambda_mover.zip"
}

data "archive_file" "backend_api_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/api/backend_api.py"
  output_path = "${path.module}/backend_api.zip"
}

module "lambda_mover" {
  source = "./modules/lambda_mover"

  project_name = local.project
  tags         = local.tags

  landing_bucket_arn = module.s3_core.landing_bucket_arn
  target_bucket_arn  = module.s3_core.target_bucket_arn
  target_bucket_name = module.s3_core.target_bucket_name
  config_bucket_arn  = module.s3_core.config_bucket_arn
  config_bucket_name = module.s3_core.config_bucket_name

  jobs_table_arn  = module.dynamodb_jobs.jobs_table_arn
  jobs_table_name = module.dynamodb_jobs.jobs_table_name

  sns_topic_arn = module.sns_alerts.sns_topic_arn

  lambda_zip_filename     = data.archive_file.lambda_zip.output_path
  lambda_source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

####################
# Backend HTTP API (Lambda + API Gateway)
####################

module "backend_api" {
  source = "./modules/backend_api"

  project_name = local.project
  tags         = local.tags
  aws_region   = var.aws_region

  jobs_table_name    = module.dynamodb_jobs.jobs_table_name
  config_bucket_name = module.s3_core.config_bucket_name
  landing_bucket_name = module.s3_core.landing_bucket_name
  target_bucket_name  = module.s3_core.target_bucket_name

  lambda_zip_filename     = data.archive_file.backend_api_zip.output_path
  lambda_source_code_hash = data.archive_file.backend_api_zip.output_base64sha256
}

####################
# Step Functions - File Flow module
####################

module "sfn_file_flow" {
  source = "./modules/sfn_file_flow"

  project_name       = local.project
  tags               = local.tags
  lambda_function_arn = module.lambda_mover.lambda_function_arn
}

####################
# EventBridge: S3 ObjectCreated -> Step Functions (module)
####################

module "eventbridge_s3_to_sfn" {
  source = "./modules/eventbridge_s3_to_sfn"

  project_name       = local.project
  tags               = local.tags
  landing_bucket_name = module.s3_core.landing_bucket_name
  state_machine_arn  = module.sfn_file_flow.state_machine_arn
}

####################
# Config object (partners.json)
####################

resource "aws_s3_object" "partners_config" {
  bucket = module.s3_core.config_bucket_name
  key    = "partners.json"

  content = templatefile("${path.module}/../config/partners.json.tmpl", {
    project      = local.project
    alerts_email = var.alerts_email
  })

  content_type = "application/json"
}

####################
# CloudWatch Alarms
####################

# Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.project}-lambda-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    FunctionName = module.lambda_mover.lambda_function_name
  }

  alarm_actions = [module.sns_alerts.sns_topic_arn]
  tags          = local.tags
}

# No arrivals in 15 minutes (custom metric, optional)
resource "aws_cloudwatch_metric_alarm" "no_arrivals" {
  alarm_name          = "${local.project}-no-arrivals-15m"
  namespace           = "BA8S/BayFlow"
  metric_name         = "FileArrived"
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "LessThanOrEqualToThreshold"
  alarm_actions       = [module.sns_alerts.sns_topic_arn]
  tags                = local.tags
}

# Step Functions failures
resource "aws_cloudwatch_metric_alarm" "sfn_failures" {
  alarm_name          = "${local.project}-sfn-failures"
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    StateMachineArn = module.sfn_file_flow.state_machine_arn
  }

  alarm_actions = [module.sns_alerts.sns_topic_arn]
  tags          = local.tags
}

####################
# Outputs
####################

output "transfer_server_id" {
  value = module.transfer_sftp.transfer_server_id
}

output "landing_bucket" {
  value = module.s3_core.landing_bucket_name
}

output "target_bucket" {
  value = module.s3_core.target_bucket_name
}

output "config_bucket" {
  value = module.s3_core.config_bucket_name
}

output "jobs_table" {
  value = module.dynamodb_jobs.jobs_table_name
}

output "backend_api_endpoint" {
  value = module.backend_api.api_endpoint
}
