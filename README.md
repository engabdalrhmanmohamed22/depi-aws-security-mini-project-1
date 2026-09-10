# Mini Project 1 — Secure AWS Web Platform (Terraform)

## 1. Project overview
A small secure web platform on AWS, built entirely with Terraform.
The app runs behind CloudFront and an internal ALB, with servers and
database hidden in private subnets, no SSH keys, full logging, and
automated daily backups.

*(Sections 2–12 will be completed as each task is finished — see the
project brief for the exact required structure.)*

## Why a budget is a security control, not only a finance tool
A budget that only sends an email is a report — someone still has to read it,
decide, and act, and by then the damage may already be done. Attaching a
**budget action** turns it into a real control: when an attacker steals a key,
the first thing they usually do is spin up expensive EC2 or RDS resources
(for crypto-mining, for example). A budget action can automatically attach a
deny policy at 90% of the monthly spend, blocking `ec2:RunInstances` and
`rds:CreateDBInstance` with no human in the loop. This does not replace IAM
least-privilege or MFA, but it is a cheap, automatic backstop against runaway
cost caused by a compromised credential.

## Identity table (Task 3)

| Identity | What it can do | Why |
|---|---|---|
| `depi-sec-developers` (IAM group) | Read-only access to the whole account (`ReadOnlyAccess`) | Developers need to inspect resources for debugging, never to change them directly |
| `depi-dev-1` (IAM user) | Whatever the group allows — nothing attached directly to the user | All permissions flow through the group, so access is managed in one place, not per-user |
| `depi-sec-ec2-role` (IAM role, EC2 only) | `AmazonSSMManagedInstanceCore` (Session Manager access) + `depi-sec-s3-app-read` (GetObject on the app bucket only) | The app servers need to be reachable via Session Manager and to read their own files — nothing more. No SSH key, no long-lived access key on the instance |
| `depi-sec-budgets-action-role` (IAM role, Budgets service only) | Attach/detach one specific IAM policy on one specific group | Least privilege for the automated cost-control action in Task 2 |

Account password policy: minimum 14 characters, upper + lower case, a
number, a symbol, and forced rotation every 90 days.

## Status
- [x] Task 1 — Repository & Terraform project skeleton
- [x] Task 2 — Budget & Budget Action
- [x] Task 3 — IAM users, groups, roles
- [x] Task 4 — VPC, subnets, routing
- [x] Task 5 — Security Groups
- [ ] Task 6 — NACLs
- [ ] Task 7 — VPC Endpoints
- [ ] Task 8 — EC2 + Session Manager
- [ ] Task 9 — EBS encryption + EFS
- [ ] Task 10 — S3 buckets
- [ ] Task 11 — RDS
- [ ] Task 12 — ALB
- [ ] Task 13 — CloudFront
- [ ] Task 14 — CloudTrail
- [ ] Task 15 — VPC Flow Logs
- [ ] Task 16 — CloudWatch alarms & dashboard
- [ ] Task 17 — Lambda auto-remediation
- [ ] Task 18 — VPC Peering
- [ ] Task 19 — AWS Backup + Vault Lock
- [ ] Task 20 — Security testing & clean-up
