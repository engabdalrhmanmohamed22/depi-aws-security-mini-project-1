# Task 9 — EFS shared file system (S3 buckets come in Task 10)
#
# EBS is one disk for one instance. EFS is one file system that many
# instances mount at the same time.

resource "aws_efs_file_system" "app" {
  encrypted = true

  tags = {
    Name = "${var.name_prefix}-efs"
  }
}

resource "aws_efs_mount_target" "private_a" {
  file_system_id  = aws_efs_file_system.app.id
  subnet_id       = aws_subnet.private_a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "private_b" {
  file_system_id  = aws_efs_file_system.app.id
  subnet_id       = aws_subnet.private_b.id
  security_groups = [aws_security_group.efs.id]
}

# Access point: a fixed POSIX identity and a dedicated root directory, so
# every app server that mounts through this access point lands in the same
# /app-data folder with the same file ownership, instead of raw root access
# to the whole file system.
resource "aws_efs_access_point" "app_data" {
  file_system_id = aws_efs_file_system.app.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/app-data"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.name_prefix}-efs-access-point"
  }
}

# ---------------------------------------------------------------------------
# Task 10 — S3 buckets that cannot leak
#
# Two buckets: one for application files, one for logs (CloudTrail/ALB/
# CloudFront logs land here in later tasks). Both private, encrypted,
# versioned, and forced to HTTPS-only.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "app" {
  bucket = "${var.name_prefix}-app-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.name_prefix}-app-bucket"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.name_prefix}-logs-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.name_prefix}-logs-bucket"
  }
}

# --- Block ALL public access on both buckets ---
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Versioning on both buckets ---
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- Default encryption (SSE-S3) on both buckets ---
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- Deny any request that is not over HTTPS ---
data "aws_iam_policy_document" "deny_insecure_transport_app" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.app.arn, "${aws_s3_bucket.app.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "app" {
  bucket = aws_s3_bucket.app.id
  policy = data.aws_iam_policy_document.deny_insecure_transport_app.json
}

data "aws_iam_policy_document" "deny_insecure_transport_logs" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket_combined.json
}

# --- Lifecycle: move noncurrent versions to Glacier after 30 days, delete after 365 ---
resource "aws_s3_bucket_lifecycle_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    id     = "noncurrent-version-lifecycle"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "noncurrent-version-lifecycle"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}
