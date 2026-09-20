# Outputs used across tasks (ALB DNS name, CloudFront domain, RDS endpoint, etc.)
# (to be filled in progressively — see project brief)

output "budget_name" {
  description = "Name of the monthly cost budget (Task 2)."
  value       = aws_budgets_budget.monthly.name
}

output "deny_expensive_policy_arn" {
  description = "ARN of the IAM policy attached automatically when the budget action fires (Task 2)."
  value       = aws_iam_policy.deny_expensive.arn
}

output "ec2_instance_profile_name" {
  description = "Instance profile name to attach to EC2 servers in Task 8."
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "ec2_role_arn" {
  description = "ARN of the EC2 instance role (Task 3)."
  value       = aws_iam_role.ec2_role.arn
}

output "app_bucket_name" {
  description = "The S3 app bucket name (Task 10)."
  value       = aws_s3_bucket.app.id
}

output "logs_bucket_name" {
  description = "The S3 logs bucket name (Task 10), used by CloudTrail/ALB/CloudFront logs later."
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "ARN of the logs bucket, needed for bucket policies in Tasks 13-14."
  value       = aws_s3_bucket.logs.arn
}

output "rds_endpoint" {
  description = "RDS connection endpoint (host:port), Task 11. Use this from an app server to test connectivity."
  value       = aws_db_instance.app.endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding the DB username/password (Task 11). Never printed in plain text."
  value       = aws_secretsmanager_secret.db_password.arn
}

output "alb_dns_name" {
  description = "ALB public DNS name (Task 12). Open this in a browser to test the site."
  value       = aws_lb.app.dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (Task 13). This is the public URL for the site — open with https://."
  value       = aws_cloudfront_distribution.app.domain_name
}

output "cloudtrail_name" {
  description = "CloudTrail trail name (Task 14)."
  value       = aws_cloudtrail.main.name
}

output "cloudtrail_log_group_name" {
  description = "CloudWatch Log group CloudTrail streams into (Task 14), for searching events."
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "flow_logs_group_name" {
  description = "CloudWatch Log group for VPC Flow Logs (Task 15)."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "sns_alerts_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms (Task 16). Confirm the email subscription after apply."
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name (Task 16)."
  value       = aws_cloudwatch_dashboard.overview.dashboard_name
}

output "remediate_lambda_name" {
  description = "Auto-remediation Lambda function name (Task 17)."
  value       = aws_lambda_function.remediate_ssh.function_name
}

output "tools_vpc_id" {
  description = "Tools VPC ID (Task 18)."
  value       = aws_vpc.tools.id
}

output "monitor_instance_id" {
  description = "Monitoring instance ID in tools-vpc (Task 18)."
  value       = aws_instance.monitor.id
}

output "peering_connection_id" {
  description = "VPC peering connection ID between app-vpc and tools-vpc (Task 18)."
  value       = aws_vpc_peering_connection.app_to_tools.id
}

output "backup_vault_name" {
  description = "AWS Backup vault name (Task 19)."
  value       = aws_backup_vault.main.name
}

output "backup_plan_id" {
  description = "AWS Backup plan ID (Task 19)."
  value       = aws_backup_plan.main.id
}

output "dev1_initial_password" {
  description = "Auto-generated initial console password for depi-dev-1. Sensitive — fetch with: terraform output -raw dev1_initial_password"
  value       = aws_iam_user_login_profile.dev_1.password
  sensitive   = true
}

output "vpc_id" {
  description = "ID of depi-sec-app-vpc (Task 4)."
  value       = aws_vpc.app.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, used by the ALB in Task 12."
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs, used by EC2/RDS/EFS in Tasks 8-11."
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "private_route_table_id" {
  description = "Private route table ID — Task 7 adds the S3 endpoint route here, Task 18 adds the peering route here."
  value       = aws_route_table.private.id
}

output "alb_sg_id" {
  description = "ALB security group ID (Task 5), used by the ALB in Task 12."
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "App servers security group ID (Task 5), used by EC2 in Task 8."
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "RDS security group ID (Task 5), used by RDS in Task 11."
  value       = aws_security_group.db.id
}

output "efs_sg_id" {
  description = "EFS security group ID (Task 5), used by EFS mount targets in Task 9."
  value       = aws_security_group.efs.id
}

output "s3_gateway_endpoint_id" {
  description = "S3 Gateway endpoint ID (Task 7)."
  value       = aws_vpc_endpoint.s3.id
}

output "interface_endpoint_ids" {
  description = "SSM / SSMMESSAGES / EC2MESSAGES interface endpoint IDs (Task 7)."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "endpoint_sg_id" {
  description = "Security group ID used by the interface endpoints (Task 7)."
  value       = aws_security_group.endpoints.id
}

output "app_instance_ids" {
  description = "EC2 app server instance IDs (Task 8) — use these to start a Session Manager session in the Console."
  value       = [aws_instance.app_a.id, aws_instance.app_b.id]
}

output "app_instance_private_ips" {
  description = "Private IPs of the app servers (Task 8), useful for Tasks 11, 18, and testing."
  value       = [aws_instance.app_a.private_ip, aws_instance.app_b.private_ip]
}

output "efs_id" {
  description = "EFS file system ID (Task 9)."
  value       = aws_efs_file_system.app.id
}

output "efs_dns_name" {
  description = "EFS DNS name used to mount the file system (Task 9)."
  value       = aws_efs_file_system.app.dns_name
}
