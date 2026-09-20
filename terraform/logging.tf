# Task 14 — CloudTrail: who did what, and when
#
# Every API call in the account gets written to a bucket we control, with a
# signed digest (log file validation) so the evidence can't be quietly
# edited or removed later.

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Combined logs bucket policy: the deny-insecure-transport statement from
# Task 10, PLUS the two statements CloudTrail needs to write into this
# bucket (ACL check + PutObject scoped to its own AWSLogs/<account-id>/
# prefix, only when it grants bucket-owner-full-control).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "logs_bucket_combined" {
  source_policy_documents = [data.aws_iam_policy_document.deny_insecure_transport_logs.json]

  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Log group the trail also streams into, so events are
# searchable without waiting for S3 delivery.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/${var.name_prefix}/cloudtrail"
  retention_in_days = 14

  tags = {
    Name = "${var.name_prefix}-cloudtrail-logs"
  }
}

data "aws_iam_policy_document" "cloudtrail_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name               = "${var.name_prefix}-cloudtrail-cw-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role.json
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name   = "${var.name_prefix}-cloudtrail-cw-permissions"
  role   = aws_iam_role.cloudtrail_cloudwatch.id
  policy = data.aws_iam_policy_document.cloudtrail_cloudwatch_permissions.json
}

# ---------------------------------------------------------------------------
# The trail itself — multi-Region, log file validation on, data events for
# S3 object-level reads on the app bucket, streamed to both S3 and
# CloudWatch Logs.
# ---------------------------------------------------------------------------
resource "aws_cloudtrail" "main" {
  name                          = "${var.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.logs.id
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  include_global_service_events = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.app.arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.logs]

  tags = {
    Name = "${var.name_prefix}-trail"
  }
}

# ---------------------------------------------------------------------------
# Task 15 — VPC Flow Logs: what crossed the network
#
# Records of every accepted and rejected connection (metadata only —
# addresses, ports, bytes, allowed or rejected — never packet content).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/${var.name_prefix}/vpc/flowlogs"
  retention_in_days = 14

  tags = {
    Name = "${var.name_prefix}-vpc-flow-logs"
  }
}

data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name_prefix}-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
}

data "aws_iam_policy_document" "flow_logs_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.name_prefix}-flow-logs-permissions"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_permissions.json
}

resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.app.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn

  tags = {
    Name = "${var.name_prefix}-vpc-flow-log"
  }
}

# ---------------------------------------------------------------------------
# Task 16 — CloudWatch: how is it performing
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Alarm 1: EC2 CPU above 70% for 2 periods of 5 minutes, per instance ---
locals {
  app_instances = {
    a = aws_instance.app_a.id
    b = aws_instance.app_b.id
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.app_instances

  alarm_name          = "${var.name_prefix}-cpu-high-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "CPU above 70% for 2 consecutive 5-minute periods on ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = each.value
  }
}

# --- Alarm 2: ALB unhealthy host count > 0 (the security-relevant one) ---
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "${var.name_prefix}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "At least one target behind the ALB is unhealthy"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.app.arn_suffix
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

# --- Alarm 3: RDS free storage below 2 GB ---
resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "${var.name_prefix}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648 # 2 GB in bytes
  alarm_description   = "RDS free storage below 2 GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.app.id
  }
}

# --- Alarm 4 (security): 3+ failed console logins in 5 minutes ---
resource "aws_cloudwatch_log_metric_filter" "failed_console_logins" {
  name           = "${var.name_prefix}-failed-console-logins"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = \"ConsoleLogin\") && ($.errorMessage = \"Failed authentication\") }"

  metric_transformation {
    name      = "${var.name_prefix}-FailedConsoleLogins"
    namespace = "${var.name_prefix}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "failed_console_logins" {
  alarm_name          = "${var.name_prefix}-failed-console-logins"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.failed_console_logins.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.failed_console_logins.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  treat_missing_data  = "notBreaching"
  alarm_description   = "3 or more failed console logins within 5 minutes — possible brute-force attempt"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# --- Dashboard: the four metrics above at a glance ---
resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EC2 CPU Utilization"
          region  = var.region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.app_a.id],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.app_b.id]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Unhealthy Host Count"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix]
          ]
          period = 60
          stat   = "Maximum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS Free Storage Space"
          region = var.region
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.app.id]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Failed Console Logins"
          region = var.region
          metrics = [
            [aws_cloudwatch_log_metric_filter.failed_console_logins.metric_transformation[0].namespace, aws_cloudwatch_log_metric_filter.failed_console_logins.metric_transformation[0].name]
          ]
          period = 300
          stat   = "Sum"
        }
      }
    ]
  })
}
