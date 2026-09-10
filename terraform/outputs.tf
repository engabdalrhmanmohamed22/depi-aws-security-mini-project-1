# ---------------------------------------------------------------------------
# Task 3 outputs
# ---------------------------------------------------------------------------

output "dev_1_console_password" {
  description = "Initial console password for depi-dev-1 (must be changed on first login)"
  value       = aws_iam_user_login_profile.dev_1.password
  sensitive   = true
}

output "dev_1_console_login_url" {
  description = "Console sign-in URL for IAM users in this account"
  value       = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}

output "ec2_instance_profile_name" {
  description = "Instance profile to attach to EC2 servers in Task 8"
  value       = aws_iam_instance_profile.ec2_profile.name
}

# ---------------------------------------------------------------------------
# Task 4 outputs
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "The app VPC ID"
  value       = aws_vpc.app.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for the ALB in Task 12)"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for EC2, RDS, EFS)"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# The rest of outputs.tf (ALB DNS name, CloudFront URL, RDS endpoint...)
# is filled in as later tasks are completed.

# ---------------------------------------------------------------------------
# Task 5 outputs
# ---------------------------------------------------------------------------

output "alb_sg_id" {
  description = "Security group for the ALB (Task 12)"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "Security group for the EC2 app servers (Task 8)"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Security group for RDS (Task 11)"
  value       = aws_security_group.db.id
}

output "efs_sg_id" {
  description = "Security group for EFS mount targets (Task 9)"
  value       = aws_security_group.efs.id
}
