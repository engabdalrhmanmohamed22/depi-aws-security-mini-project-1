# Task 17 — Auto-remediation Lambda + EventBridge rule
#
# The remediation path:
#   Someone opens port 22 -> CloudTrail records the API call
#   -> EventBridge rule matches AuthorizeSecurityGroupIngress
#   -> Lambda reads the group, finds 0.0.0.0/0:22, revokes it
#   -> SNS sends the email -> rule is gone

data "archive_file" "remediate_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/remediate.py"
  output_path = "${path.module}/lambda/remediate.zip"
}

# ---------------------------------------------------------------------------
# IAM role — least privilege: describe/revoke security groups, publish to
# the one alerts topic, and write its own CloudWatch Logs. Nothing more.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "remediate_lambda" {
  name               = "${var.name_prefix}-remediate-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "remediate_lambda_permissions" {
  statement {
    sid    = "SecurityGroupRemediation"
    effect = "Allow"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:RevokeSecurityGroupIngress"
    ]
    resources = ["*"] # EC2 security group actions do not support resource-level restriction
  }

  statement {
    sid       = "PublishAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "LambdaOwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.name_prefix}-remediate-ssh:*"]
  }
}

resource "aws_iam_role_policy" "remediate_lambda_permissions" {
  name   = "${var.name_prefix}-remediate-lambda-permissions"
  role   = aws_iam_role.remediate_lambda.id
  policy = data.aws_iam_policy_document.remediate_lambda_permissions.json
}

# ---------------------------------------------------------------------------
# The function itself
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "remediate_ssh" {
  function_name    = "${var.name_prefix}-remediate-ssh"
  role             = aws_iam_role.remediate_lambda.arn
  handler          = "remediate.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.remediate_lambda.output_path
  source_code_hash = data.archive_file.remediate_lambda.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  tags = {
    Name = "${var.name_prefix}-remediate-ssh"
  }
}

# ---------------------------------------------------------------------------
# EventBridge rule — matches the exact CloudTrail event for opening an
# inbound Security Group rule, from any source.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "ssh_opened" {
  name        = "${var.name_prefix}-ssh-opened"
  description = "Matches AuthorizeSecurityGroupIngress calls recorded by CloudTrail"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AuthorizeSecurityGroupIngress"]
    }
  })
}

resource "aws_cloudwatch_event_target" "invoke_remediate" {
  rule      = aws_cloudwatch_event_rule.ssh_opened.name
  target_id = "${var.name_prefix}-remediate-lambda"
  arn       = aws_lambda_function.remediate_ssh.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_ssh.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ssh_opened.arn
}
