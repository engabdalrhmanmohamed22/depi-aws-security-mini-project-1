# ---------------------------------------------------------------------------
# Task 2 — supporting IAM pieces used by the budget action
# (User/role/policy work for people is completed in Task 3)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Denies launching new EC2 instances or RDS databases.
# Attached automatically to the developers group once spend crosses 90%.
resource "aws_iam_policy" "deny_expensive" {
  name        = "${var.project_name}-deny-expensive"
  description = "Denies EC2 RunInstances and RDS CreateDBInstance. Auto-attached by the monthly budget action."

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

# Group used by Task 3 for developer users, and targeted by the
# budget action defined in budget.tf.
resource "aws_iam_group" "developers" {
  name = "${var.project_name}-developers"
}

# Role that the AWS Budgets service assumes in order to execute the
# budget action (attach/detach the deny policy on our behalf).
resource "aws_iam_role" "budgets_action_role" {
  name = "${var.project_name}-budgets-action-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "budgets_action_permissions" {
  name = "${var.project_name}-budgets-action-permissions"
  role = aws_iam_role.budgets_action_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachGroupPolicy",
          "iam:DetachGroupPolicy",
          "iam:GetPolicy",
          "iam:GetGroupPolicy",
          "iam:ListAttachedGroupPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Task 3 — Identity: users, groups, roles, and least privilege
# ---------------------------------------------------------------------------

# 1. Account-wide password policy: strong passwords, forced rotation.
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  max_password_age               = 90
  allow_users_to_change_password = true
}

# 2. Give the developers group (created in Task 2) read-only access.
#    Developers can look at everything, change nothing.
resource "aws_iam_group_policy_attachment" "developers_readonly" {
  group      = aws_iam_group.developers.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 3. A single developer console user, member of the group above,
#    with no direct policies attached to the user itself.
resource "aws_iam_user" "dev_1" {
  name          = "depi-dev-1"
  force_destroy = true
}

resource "aws_iam_user_login_profile" "dev_1" {
  user                    = aws_iam_user.dev_1.name
  password_length         = 20
  password_reset_required = true
  # No pgp_key is supplied, so Terraform stores the generated password in
  # the state file in clear text. This is acceptable ONLY because Task 1's
  # .gitignore keeps *.tfstate out of version control.
}

resource "aws_iam_user_group_membership" "dev_1_membership" {
  user   = aws_iam_user.dev_1.name
  groups = [aws_iam_group.developers.name]
}

# 4. Customer-managed policy: read-only access to ONE bucket, nothing else.
#    No wildcard bucket, no write/delete/list-all-buckets permission.
resource "aws_iam_policy" "s3_app_read" {
  name        = "${var.project_name}-s3-app-read"
  description = "Allows GetObject on the app bucket only. No other S3 permission."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAppBucketReadOnly"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.project_name}-app-${random_id.app_bucket_suffix.hex}/*"
      }
    ]
  })
}

# 5. EC2 instance role: only what the app servers actually need —
#    Session Manager connectivity, and read-only access to the app bucket.
#    No SSH key, no long-lived access key stored on the instance.
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_app_read.arn
}

# 6. Instance profile — this is what actually gets attached to an EC2
#    instance in Task 8. A role by itself cannot be attached to an instance.
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}
