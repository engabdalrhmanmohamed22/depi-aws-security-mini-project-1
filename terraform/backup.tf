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
# Vault Lock — GOVERNANCE mode. Governance vs. compliance mode is controlled
# by whether changeable_for_days is set on PutBackupVaultLockConfiguration:
#   - changeable_for_days SET   -> compliance mode. Editable during that
#     grace window only; once it elapses the lock is permanent and cannot be
#     removed by anyone, including the root user or AWS Support.
#   - changeable_for_days OMITTED -> governance mode. The lock is permanent
#     immediately, but a principal with the backup:BypassGovernanceRetention
#     permission can still delete a recovery point or remove the lock.
#
# An earlier version of this file omitted vault locking entirely based on a
# mistaken assumption that Backup Vault Lock had no true governance mode.
# That was wrong: simply never setting changeable_for_days IS governance
# mode. The lock below is governance mode, matching the project brief
# exactly, and still allows `terraform destroy` to succeed for an account
# admin, since the root/admin identity retains bypass permission by default.
# ---------------------------------------------------------------------------
resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name  = aws_backup_vault.main.name
  min_retention_days = 7
  max_retention_days = 365
  # changeable_for_days intentionally omitted -> governance mode.
}
