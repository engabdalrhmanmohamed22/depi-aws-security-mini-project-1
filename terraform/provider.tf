provider "aws" {
  region = var.region

  # Applied automatically to every resource that supports tags.
  # This is why individual resources below do NOT repeat these tags by hand.
  default_tags {
    tags = {
      Project     = var.project_name
      Owner       = var.owner
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }

  # No access_key / secret_key here on purpose.
  # The provider picks up credentials automatically from:
  #   1. Environment variables (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY), or
  #   2. The local ~/.aws/credentials file created by `aws configure`.
  # Never hard-code credentials in any .tf file.
}
