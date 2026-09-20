# Task 3 — Identity: password policy, developers group/user, EC2 role, instance profile

# ---------------------------------------------------------------------------
# 0. depi-sec-developers group.
#    (Referenced by Task 2's budget.tf as the target of the Budget Action.)
# ---------------------------------------------------------------------------
resource "aws_iam_group" "developers" {
  name = "${var.name_prefix}-developers"
}

# ---------------------------------------------------------------------------
# 1. Shared random suffix for globally-unique S3 bucket names.
#    Declared here because the s3-app-read policy below needs to reference
#    the exact bucket name; the buckets themselves are created in Task 10
#    (storage.tf) using this SAME random_id resource.
# ---------------------------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ---------------------------------------------------------------------------
# 2. Account-wide password policy
# ---------------------------------------------------------------------------
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  max_password_age               = 90
  allow_users_to_change_password = true
}

# ---------------------------------------------------------------------------
# 3. depi-sec-developers group's actual day-to-day permission: read-only
#    access, nothing more.
# ---------------------------------------------------------------------------
resource "aws_iam_group_policy_attachment" "developers_readonly" {
  group      = aws_iam_group.developers.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ---------------------------------------------------------------------------
# 4. depi-dev-1 user — console access, member of the group, ZERO direct
#    policies (all its permissions come from the group it belongs to).
# ---------------------------------------------------------------------------
resource "aws_iam_user" "dev_1" {
  name = "depi-dev-1"
}

resource "aws_iam_user_login_profile" "dev_1" {
  user                    = aws_iam_user.dev_1.name
  password_reset_required = true
  # Terraform auto-generates a strong initial password (never hard-coded here).
  # Retrieve it once after apply with: terraform output -raw dev1_initial_password
}

resource "aws_iam_group_membership" "developers_membership" {
  name  = "${var.name_prefix}-developers-membership"
  group = aws_iam_group.developers.name
  users = [aws_iam_user.dev_1.name]
}

# ---------------------------------------------------------------------------
# 5. Customer-managed policy: read-only access to ONE bucket only, no
#    wildcard bucket. Used by the EC2 role below.
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "s3_app_read" {
  name        = "${var.name_prefix}-s3-app-read"
  description = "Allows s3:GetObject on the app bucket only. No wildcard bucket, no other action."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAppBucketOnly"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.name_prefix}-app-${random_id.bucket_suffix.hex}/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# 6. EC2 instance role — assumable only by EC2, carries SSM (for
#    Session-Manager-only access, no SSH) plus the scoped S3 read policy.
#    This is what makes Task 8's "no key pair, no public IP" servers work.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_app_read.arn
}

# The instance profile is what actually gets attached to an EC2 instance
# (Task 8 references aws_iam_instance_profile.ec2_profile.name directly in
# the aws_instance resource — never attached by hand in the Console).
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}
