# Security Controls

This document lists every security control in the platform: the control,
the AWS service, the threat it stops, and the screenshot that proves it.
This is the document a security reviewer should read first.

## Task 5 — Security Groups: the tiered firewall

```
Internet (0.0.0.0/0)
      |
      | TCP 80
      v
+---------------+
|  depi-sec-    |   <- the ONLY security group open to the internet
|  alb-sg       |
+---------------+
      |
      | TCP 80  (source = alb-sg, not a CIDR)
      v
+---------------+
|  depi-sec-    |
|  app-sg       |
+---------------+
      |
      +---------------------------+
      |                           |
      | TCP 3306 (source=app-sg)  | TCP 2049 (source=app-sg)
      v                           v
+---------------+           +---------------+
|  depi-sec-    |           |  depi-sec-    |
|  db-sg        |           |  efs-sg       |
+---------------+           +---------------+
```

Each group only trusts the group directly above it — never a raw IP range,
never "anywhere." A security group reference follows the instances wherever
they move, so the rule stays correct even if a subnet or IP changes later.
No group anywhere has an inbound rule for port 22 (SSH); the only access
path into the servers is Session Manager (Task 8).

## Control table (filled in as each task is completed)

| Control | AWS Service | Threat it stops | Screenshot |
|---|---|---|---|
| Deny-expensive budget action | AWS Budgets + IAM | Runaway cost from a compromised credential launching EC2/RDS | `02-budget/` |
| Least-privilege IAM (group, role, scoped policy) | IAM | Over-permissioned users/instances; blast radius of a leaked credential | `03-iam/` |
| Public/private subnet split | VPC routing | Direct internet access to app servers and database | `04-vpc/` |
| Tiered Security Groups (this task) | EC2 Security Groups | Lateral movement; direct access to DB/EFS from outside the app tier | `05-sg/` |
| NACL deny on port 22 | VPC NACL | SSH access to private subnets even if a Security Group is misconfigured | `06-nacl/` (Task 6) |
| No SSH keys, Session Manager only | IAM + SSM | Leaked/stolen SSH keys, open port 22 | `08-ec2/` (Task 8) |
| Private RDS, encrypted storage | RDS | Public database access; data exposure at rest | `11-rds/` (Task 11) |
| S3 Block Public Access + deny-insecure-transport | S3 | Accidental public bucket; unencrypted data in transit | `10-s3/` (Task 10) |
| Secret header between CloudFront and ALB | CloudFront + ALB listener rule | Bypassing CloudFront/WAF by hitting the ALB directly | `13-cloudfront/` (Task 13) |
| CloudTrail with log file validation | CloudTrail | Tampering with audit evidence after an incident | `14-cloudtrail/` (Task 14) |
| VPC Flow Logs | VPC + CloudWatch Logs | Undetected network reconnaissance or exfiltration attempts | `15-flowlogs/` (Task 15) |
| Auto-remediation Lambda | Lambda + EventBridge | An open 0.0.0.0/0:22 rule staying open for hours before a human notices | `17-lambda/` (Task 17) |
| AWS Backup + Vault Lock (governance) | AWS Backup | Ransomware deleting backups before encrypting data | `19-backup/` (Task 19) |
