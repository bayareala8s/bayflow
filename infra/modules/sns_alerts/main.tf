####################
# SNS Alerts module
####################

variable "project_name" {
  type        = string
  description = "Project name used for naming the SNS topic"
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
}

variable "alerts_email" {
  type        = string
  description = "Email address for SNS alerts subscription"
}

####################
# SNS Topic & Subscription
####################

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alerts_email
}

####################
# Outputs
####################

output "sns_topic_arn" {
  description = "ARN of the alerts SNS topic"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the alerts SNS topic"
  value       = aws_sns_topic.alerts.name
}
