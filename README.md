# Mini Project 1 — Secure AWS Web Platform (Terraform)

Status: 🚧 In progress — Task 1 (repository & Terraform bootstrap) complete.

## 1. Project overview
Coming soon (Task 20 wrap-up).

## 2. Architecture diagram
See [`docs/architecture.md`](docs/architecture.md).

## 3. Network design table
See [`docs/architecture.md`](docs/architecture.md).

## 4. Security controls table
See [`docs/security-controls.md`](docs/security-controls.md).

### Identity table (Task 3)

| Identity | What it can do | Why |
|---|---|---|
| `depi-sec-developers` (IAM group) | Read-only access to the whole account (`ReadOnlyAccess`) | Developers can inspect resources for debugging without any ability to change or delete anything |
| `depi-dev-1` (IAM user) | Whatever the group allows — **zero direct policies** | All permissions flow from group membership, never from the user directly, so access is auditable and consistent in one place |
| `depi-sec-ec2-role` (IAM role, assumed by EC2 only) | `AmazonSSMManagedInstanceCore` (Session Manager access, no SSH) + `depi-sec-s3-app-read` (read-only on one named bucket) | Servers need to be reachable for management (via SSM) and need to read their own app files — nothing more. Short-lived, auto-rotated credentials instead of a static access key baked into the instance |



## 5. Prerequisites
- Terraform >= 1.6
- AWS CLI v2, configured with `aws configure` (credentials are **never** stored in this repo)
- An AWS account with permissions to create IAM, VPC, EC2, RDS, S3, CloudFront, Lambda, Backup, and Budgets resources

## 6. How to deploy
```bash
cd terraform
terraform init
terraform plan
terraform apply
```
Required variable (set in a local, git-ignored `terraform.tfvars`, **not** committed):
```hcl
alert_email = "your-email@example.com"
```

## 7. How to verify
See [`docs/testing.md`](docs/testing.md) — filled in at Task 20.

## 8. Screenshots
Grouped under [`screenshots/`](screenshots/) by task number.

## 9. Cost notes

### Why a budget is a security control, not only a finance tool (Task 2)
A budget that only *reports* spend is a dashboard — a human has to see the email and react in time.
A budget with an **action** is a guardrail: at 90% of the $10 monthly limit, AWS automatically attaches
`depi-sec-deny-expensive` to the `depi-sec-developers` group, which denies `ec2:RunInstances` and
`rds:CreateDBInstance`. This matters because the most common outcome of a stolen AWS access key is
an attacker launching many expensive instances (for crypto-mining, for example) before anyone notices.
The two email notifications (80% actual, 100% forecasted) give early warning, but the automatic action
at 90% stops the bleeding even if nobody reads the email in time — the same logic as an automatic
circuit breaker, applied to cost instead of amps.

Coming soon: full Task 20 cost notes (real cost paid, Cost Explorer total).

## 10. How to destroy
```bash
cd terraform
terraform destroy
```
Empty both S3 buckets (including old versions) first, or the destroy will fail.

## 11. What I learned
Coming soon (Task 20).

## 12. Known limitations
Coming soon (Task 20).
