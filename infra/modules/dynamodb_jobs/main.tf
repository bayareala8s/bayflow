variable "project_name" {
  description = "Short project name used as prefix for AWS resources (e.g. bayflow-poc)"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to DynamoDB resources"
  type        = map(string)
}

####################
# DynamoDB - Job Tracking
####################

resource "aws_dynamodb_table" "jobs" {
  name         = "${var.project_name}-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"
  range_key    = "file_name"

  attribute {
    name = "job_id"
    type = "S"
  }

  attribute {
    name = "file_name"
    type = "S"
  }

  # Tenant + flow for future querying
  attribute {
    name = "tenant"
    type = "S"
  }

  attribute {
    name = "flow_id"
    type = "S"
  }

  global_secondary_index {
    name            = "tenant_flow_idx"
    hash_key        = "tenant"
    range_key       = "flow_id"
    projection_type = "ALL"
  }

  tags = var.tags
}

output "jobs_table_arn" {
  description = "ARN of the DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.arn
}

output "jobs_table_name" {
  description = "Name of the DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.name
}
