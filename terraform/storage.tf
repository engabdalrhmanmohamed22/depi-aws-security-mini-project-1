# ---------------------------------------------------------------------------
# Random suffix for the app S3 bucket.
# Declared early (Task 3 needs it to scope the s3-app-read IAM policy to an
# exact bucket ARN) — the actual bucket resource is created in Task 10.
# ---------------------------------------------------------------------------
resource "random_id" "app_bucket_suffix" {
  byte_length = 4
}

# The rest of storage.tf (S3 buckets, policies, lifecycle rules) is
# completed in Task 10.
