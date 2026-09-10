provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "depi-mini-project-1"
      Owner       = var.owner_name
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }
}
