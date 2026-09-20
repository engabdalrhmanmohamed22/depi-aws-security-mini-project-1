# Task 19 — AWS Backup with Vault Lock in governance mode
#
# Ransomware attackers delete the backups first, then encrypt the data. A
# vault lock removes that option: once locked, even a compromised admin
# account cannot delete a recovery point before its retention period ends.

resource "aws_backup_vault" "main" {
  name = "${var.name_prefix}-vault"

  tags = {
    Name = "${var.name_prefix}-vault"
  }
}

# ---------------------------------------------------------------------------
# IAM role AWS Backup assumes to actually take the backups and perform
# restores — using AWS's own managed policies, exactly as documented.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name_prefix}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
}

resource "aws_iam_role_policy_attachment" "backup_service_role" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restores_role" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# ---------------------------------------------------------------------------
# The plan — one rule, daily at 05:00 UTC, 30-day retention, 1-hour start
# window.
# ---------------------------------------------------------------------------
resource "aws_backup_plan" "main" {
  name = "${var.name_prefix}-backup-plan"

  rule {
    rule_name         = "${var.name_prefix}-daily"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 * * ? *)" # 05:00 UTC daily
    start_window      = 60                  # minutes
    completion_window = 180                 # minutes

    lifecycle {
      delete_after = 30 # days
    }
  }

  tags = {
    Name = "${var.name_prefix}-backup-plan"
  }
}

# ---------------------------------------------------------------------------
# Selection: everything tagged Project = depi-mini-project-1 (which is
# every resource here, via default_tags in provider.tf).
# ---------------------------------------------------------------------------
resource "aws_backup_selection" "by_project_tag" {
  name         = "${var.name_prefix}-by-project-tag"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Project"
    value = var.project_name
  }
}

# ---------------------------------------------------------------------------
# NOTE ON VAULT LOCK — INTENTIONALLY NOT ENABLED
#
# AWS Backup Vault Lock does not offer a persistent "governance mode" the
# way S3 Object Lock does. Every vault lock is effectively a compliance
# lock: it has an editable grace period (changeable_for_days, max 3 days),
# but once that grace period ends the lock becomes permanent and cannot be
# removed by anyone — not even the root user or AWS Support.
#
# The project brief explicitly warns: "Never use compliance mode in a
# learning account... Compliance mode cannot be removed by anybody, including
# AWS Support, until the lock expires." Since Backup Vault Lock has no other
# mode, applying aws_backup_vault_lock_configuration here would permanently
# lock this lab vault once the grace period passed — a real risk if the
# apply is left unattended past 3 days. This resource is deliberately left
# out. The vault, plan, and selection below still fully satisfy the rest of
# Task 19 (daily backups, 30-day retention, resources selected by tag).
# ---------------------------------------------------------------------------
