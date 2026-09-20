variable "project_name" {
  description = "Short name used to tag every resource (Project tag)."
  type        = string
  default     = "depi-mini-project-1"
}

variable "name_prefix" {
  description = "Fixed prefix put on every resource name, per project rules."
  type        = string
  default     = "depi-sec"
}

variable "region" {
  description = "Single AWS Region used for the whole project."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Your name, used for the Owner tag."
  type        = string
  default     = "Abdalrahman Aldessouki"
}

variable "vpc_cidr" {
  description = "CIDR block for the main application VPC (depi-sec-app-vpc)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "tools_vpc_cidr" {
  description = "CIDR block for the secondary tools/monitoring VPC (depi-sec-tools-vpc). Must not overlap vpc_cidr."
  type        = string
  default     = "10.1.0.0/16"
}

variable "alert_email" {
  description = "Email address that receives Budget alerts, CloudWatch alarm emails, and Lambda remediation notifications. Set this in a local terraform.tfvars file (git-ignored) — do not hard-code it here."
  type        = string
}
