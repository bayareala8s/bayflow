variable "project_name" {
  description = "Short project name used as prefix for AWS resources (e.g. bayflow-poc)"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to backend API resources"
  type        = map(string)
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "jobs_table_name" {
  description = "Name of the DynamoDB jobs table"
  type        = string
}

variable "config_bucket_name" {
  description = "Name of the config S3 bucket (for partners.json)"
  type        = string
}

variable "landing_bucket_name" {
  description = "Name of the landing S3 bucket"
  type        = string
}

variable "target_bucket_name" {
  description = "Name of the target S3 bucket"
  type        = string
}

variable "lambda_zip_filename" {
  description = "Path to the backend API Lambda zip"
  type        = string
}

variable "lambda_source_code_hash" {
  description = "Source code hash for the backend API Lambda zip"
  type        = string
}

####################
# IAM for backend API Lambda
####################

data "aws_iam_policy_document" "api_lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "api_lambda_policy" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    actions = ["dynamodb:Query", "dynamodb:Scan"]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:*:table/${var.jobs_table_name}",
      "arn:aws:dynamodb:${var.aws_region}:*:table/${var.jobs_table_name}/index/*",
    ]
  }

  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.config_bucket_name}",
      "arn:aws:s3:::${var.config_bucket_name}/*",
      "arn:aws:s3:::${var.landing_bucket_name}",
      "arn:aws:s3:::${var.landing_bucket_name}/*",
      "arn:aws:s3:::${var.target_bucket_name}",
      "arn:aws:s3:::${var.target_bucket_name}/*",
    ]
  }
}

resource "aws_iam_role" "api_lambda_role" {
  name               = "${var.project_name}-api-role"
  assume_role_policy = data.aws_iam_policy_document.api_lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_policy" "api_lambda_policy" {
  name   = "${var.project_name}-api-policy"
  policy = data.aws_iam_policy_document.api_lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "api_lambda_attach" {
  role       = aws_iam_role.api_lambda_role.name
  policy_arn = aws_iam_policy.api_lambda_policy.arn
}

resource "aws_cloudwatch_log_group" "api_lg" {
  name              = "/aws/lambda/${var.project_name}-api"
  retention_in_days = 14
  tags              = var.tags
}

####################
# Backend API Lambda
####################

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-api"
  handler       = "backend_api.handler"
  runtime       = "python3.10"
  filename      = var.lambda_zip_filename
  source_code_hash = var.lambda_source_code_hash
  role          = aws_iam_role.api_lambda_role.arn

  environment {
    variables = {
      JOBS_TABLE    = var.jobs_table_name
      CONFIG_BUCKET = var.config_bucket_name

      LANDING_BUCKET = var.landing_bucket_name
      TARGET_BUCKET  = var.target_bucket_name
    }
  }

  tags = var.tags
}

####################
# HTTP API Gateway
####################

resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  integration_method     = "POST"
}

resource "aws_apigatewayv2_route" "jobs_list" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /jobs"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "job_detail" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /jobs/{job_id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "partners_get" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /partners"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "partners_put" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "PUT /partners"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "bucket_objects" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /buckets/{kind}/objects"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGWInvokeBackendApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

output "api_endpoint" {
  description = "Base URL of the backend HTTP API"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}
