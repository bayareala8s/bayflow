####################
# Lambda mover module
####################

variable "project_name" {
  type        = string
  description = "Project name used for naming Lambda and log group"
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
}

variable "landing_bucket_arn" {
  type        = string
  description = "ARN of the landing S3 bucket"
}

variable "target_bucket_arn" {
  type        = string
  description = "ARN of the target S3 bucket"
}

variable "target_bucket_name" {
  type        = string
  description = "Name of the target S3 bucket"
}

variable "config_bucket_arn" {
  type        = string
  description = "ARN of the config S3 bucket"
}

variable "config_bucket_name" {
  type        = string
  description = "Name of the config S3 bucket"
}

variable "jobs_table_arn" {
  type        = string
  description = "ARN of the DynamoDB jobs table"
}

variable "jobs_table_name" {
  type        = string
  description = "Name of the DynamoDB jobs table"
}

variable "sns_topic_arn" {
  type        = string
  description = "ARN of the SNS alerts topic"
}

variable "lambda_zip_filename" {
  type        = string
  description = "Path to the Lambda deployment package zip file"
}

variable "lambda_source_code_hash" {
  type        = string
  description = "Base64-encoded SHA256 hash of the Lambda deployment package"
}

####################
# CloudWatch Logs
####################

resource "aws_cloudwatch_log_group" "lambda_lg" {
  name              = "/aws/lambda/${var.project_name}-mover"
  retention_in_days = 14
  tags              = var.tags
}

####################
# Lambda IAM
####################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_policy" {
  # Logging
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  # S3 access
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:PutObjectTagging"
    ]

    resources = [
      var.landing_bucket_arn, "${var.landing_bucket_arn}/*",
      var.target_bucket_arn,  "${var.target_bucket_arn}/*",
      var.config_bucket_arn,  "${var.config_bucket_arn}/*"
    ]
  }

  # CloudWatch metrics (if used from Lambda)
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }

  # SNS publish
  statement {
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }

  # DynamoDB job tracking
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]
    resources = [var.jobs_table_arn]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

####################
# Lambda Function (mover)
####################

resource "aws_lambda_function" "mover" {
  function_name    = "${var.project_name}-mover"
  role             = aws_iam_role.lambda_role.arn
  handler          = "app.handler"
  runtime          = "python3.10"
  filename         = var.lambda_zip_filename
  source_code_hash = var.lambda_source_code_hash

  environment {
    variables = {
      CONFIG_BUCKET = var.config_bucket_name
      CONFIG_KEY    = "partners.json"
      METRIC_NS     = "BA8S/BayFlow"
      SNS_TOPIC_ARN = var.sns_topic_arn
      TARGET_BUCKET = var.target_bucket_name
      JOBS_TABLE    = var.jobs_table_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_lg]
  tags       = var.tags
}

####################
# Outputs
####################

output "lambda_function_arn" {
  description = "ARN of the mover Lambda function"
  value       = aws_lambda_function.mover.arn
}

output "lambda_function_name" {
  description = "Name of the mover Lambda function"
  value       = aws_lambda_function.mover.function_name
}
