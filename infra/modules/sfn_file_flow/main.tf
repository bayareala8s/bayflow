####################
# Step Functions file flow module
####################

variable "project_name" {
  type        = string
  description = "Project name used for naming the state machine and IAM role"
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
}

variable "lambda_function_arn" {
  type        = string
  description = "ARN of the mover Lambda function to invoke"
}

####################
# Step Functions IAM
####################

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn_role" {
  name               = "${var.project_name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "sfn_policy" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [var.lambda_function_arn]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "sfn_policy" {
  name   = "${var.project_name}-sfn-policy"
  policy = data.aws_iam_policy_document.sfn_policy.json
}

resource "aws_iam_role_policy_attachment" "sfn_attach" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_policy.arn
}

####################
# Step Functions State Machine
####################

resource "aws_sfn_state_machine" "file_flow" {
  name     = "${var.project_name}-file-flow"
  role_arn = aws_iam_role.sfn_role.arn

  definition = jsonencode({
    Comment = "BayFlow v1 file transfer flow"
    StartAt = "MoveFile"
    States = {
      MoveFile = {
        Type       = "Task"
        Resource   = "arn:aws:states:::lambda:invoke"
        OutputPath = "$.Payload"
        Parameters = {
          FunctionName = var.lambda_function_arn
          Payload = {
            "s3_detail.$"    = "$.detail"
            "execution_id.$" = "$$.Execution.Id"
          }
        }
        Retry = [
          {
            ErrorEquals      = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds  = 2
            MaxAttempts      = 3
            BackoffRate      = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "Failure"
          }
        ]
        Next = "Success"
      }
      Success = {
        Type = "Succeed"
      }
      Failure = {
        Type  = "Fail"
        Cause = "Mover Lambda failed"
      }
    }
  })

  tags = var.tags
}

####################
# Outputs
####################

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.file_flow.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.file_flow.name
}
