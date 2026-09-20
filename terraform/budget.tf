# Task 2 — Cost governance: budget, deny-expensive policy, budget action
#
# A budget that only sends an email is a report. A budget with an action is a
# control: at 90% of the monthly limit, AWS automatically attaches a policy
# that denies launching new (expensive) EC2 and RDS instances to the
# developers group — no human has to react in time.

# ---------------------------------------------------------------------------
# 1. The deny policy itself
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "deny_expensive" {
  name        = "${var.name_prefix}-deny-expensive"
  description = "Denies launching new EC2 instances and RDS instances. Attached automatically by a Budget Action once spend crosses the threshold."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyExpensiveActions"
        Effect   = "Deny"
        Action   = [
          "ec2:RunInstances",
          "rds:CreateDBInstance"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# 2. A role that the AWS Budgets service can assume, so it is allowed to
#    attach/detach the deny policy on our behalf when the action fires.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "budgets_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "budget_action_role" {
  name               = "${var.name_prefix}-budget-action-role"
  assume_role_policy = data.aws_iam_policy_document.budgets_assume_role.json
}

data "aws_iam_policy_document" "budget_action_permissions" {
  statement {
    sid    = "ManageDenyPolicyAttachment"
    effect = "Allow"
    actions = [
      "iam:AttachGroupPolicy",
      "iam:DetachGroupPolicy",
      "iam:ListAttachedGroupPolicies"
    ]
    resources = [aws_iam_group.developers.arn]
  }
}

resource "aws_iam_role_policy" "budget_action_permissions" {
  name   = "${var.name_prefix}-budget-action-permissions"
  role   = aws_iam_role.budget_action_role.id
  policy = data.aws_iam_policy_document.budget_action_permissions.json
}

# ---------------------------------------------------------------------------
# 3. The monthly cost budget, with two email notifications
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert 1: email when we have ALREADY spent 80% of the limit.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # Alert 2: email when we are FORECASTED to reach 100% of the limit.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ---------------------------------------------------------------------------
# 4. The budget ACTION: at 90% actual spend, automatically attach the deny
#    policy to the developers group. approval_model = AUTOMATIC means no
#    human has to click "approve" — the control fires by itself.
# ---------------------------------------------------------------------------
resource "aws_budgets_budget_action" "deny_on_overspend" {
  budget_name        = aws_budgets_budget.monthly.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budget_action_role.arn

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
    subscription_type = "EMAIL"
    address            = var.alert_email
  }
}
