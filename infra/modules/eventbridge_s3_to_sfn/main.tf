variable "project_name" {
  description = "Short project name used as prefix for AWS resources (e.g. bayflow-poc)"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to EventBridge resources"
  type        = map(string)
}

variable "landing_bucket_name" {
  description = "Name of the landing S3 bucket"
  type        = string
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine to invoke"
  type        = string
}

####################
# EventBridge: S3 ObjectCreated -> Step Functions
####################

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events_invoke_sfn_role" {
  name               = "${var.project_name}-events-invoke-sfn"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "events_invoke_sfn_policy" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [var.state_machine_arn]
  }
}

resource "aws_iam_policy" "events_invoke_sfn_policy" {
  name   = "${var.project_name}-events-invoke-sfn-policy"
  policy = data.aws_iam_policy_document.events_invoke_sfn_policy.json
}

resource "aws_iam_role_policy_attachment" "events_invoke_sfn_attach" {
  role       = aws_iam_role.events_invoke_sfn_role.name
  policy_arn = aws_iam_policy.events_invoke_sfn_policy.arn
}

resource "aws_cloudwatch_event_rule" "s3_put_to_sfn" {
  name        = "${var.project_name}-s3-put-to-sfn"
  description = "Route S3 ObjectCreated from landing bucket to BayFlow state machine"

  event_pattern = jsonencode({
    "source"      : ["aws.s3"],
    "detail-type" : ["Object Created"],
    "detail" : {
      "bucket" : {
        "name" : [var.landing_bucket_name]
      },
      "object" : {
        "key" : [{
          "prefix" : "partners/"
        }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "s3_put_to_sfn_target" {
  rule      = aws_cloudwatch_event_rule.s3_put_to_sfn.name
  target_id = "StartFileFlow"
  arn       = var.state_machine_arn
  role_arn  = aws_iam_role.events_invoke_sfn_role.arn
}

output "rule_name" {
  description = "Name of the S3->SFN EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_put_to_sfn.name
}

output "rule_arn" {
  description = "ARN of the S3->SFN EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_put_to_sfn.arn
}
