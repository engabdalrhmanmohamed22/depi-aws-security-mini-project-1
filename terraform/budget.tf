# ---------------------------------------------------------------------------
# Task 2 — Cost governance as a security control
# A budget that only emails you is a report. A budget with an action
# is a control: it can stop new spending automatically.
# ---------------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Email at 80% of ACTUAL cost already spent
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # Email at 100% of FORECASTED cost for the month
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# At 90% of actual spend, automatically attach the deny-expensive policy
# to the developers group. approval_model = AUTOMATIC means no human
# has to click "approve" — the control fires by itself.
resource "aws_budgets_budget_action" "deny_at_90_percent" {
  budget_name        = aws_budgets_budget.monthly.name
  account_id         = data.aws_caller_identity.current.account_id
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_action_role.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 90
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.deny_expensive.arn
      groups     = [aws_iam_group.developers.name]
    }
  }

  subscriber {
    address           = var.alert_email
    subscription_type = "EMAIL"
  }
}
