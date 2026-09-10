variable "project_name" {
  description = "Prefix used on every resource name"
  type        = string
  default     = "depi-sec"
}

variable "region" {
  description = "AWS region used for the whole project"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "The two AZs used across the project"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "CIDR block for the main app VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tools_vpc_cidr" {
  description = "CIDR block for the tools/monitoring VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "alert_email" {
  description = "Email address that receives budget, SNS and backup alerts"
  type        = string
  # Set this in terraform.tfvars (not committed to git)
}

variable "owner_name" {
  description = "Your name, used in default_tags"
  type        = string
  default     = "student"
}
