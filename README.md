# Mini Project 1 — Secure AWS Web Platform (Terraform)

Status: ✅ Complete — all 20 tasks implemented and tested.

## 1. Project overview
This project builds a small company web platform on AWS entirely with Terraform: a two-AZ VPC with
public and private subnets, an EC2 web tier behind an Application Load Balancer and CloudFront, a
private RDS MySQL database, and a shared EFS file system. Every management action is recorded by
CloudTrail, every network flow by VPC Flow Logs, and a Lambda function automatically reverses any
attempt to open SSH to the internet. Nothing except the load balancer and CloudFront has a public IP;
servers are reached only through AWS Systems Manager Session Manager, with no SSH keys anywhere. A
second, peered VPC hosts a monitoring instance representing a separate operational trust boundary.

## 2. Architecture diagram
See [`docs/architecture.md`](docs/architecture.md).

## 3. Network design table

| VPC | CIDR | Subnet | CIDR | AZ | Type |
|---|---|---|---|---|---|
| depi-sec-app-vpc | 10.0.0.0/16 | depi-sec-public-a | 10.0.1.0/24 | us-east-1a | Public |
| depi-sec-app-vpc | 10.0.0.0/16 | depi-sec-public-b | 10.0.2.0/24 | us-east-1b | Public |
| depi-sec-app-vpc | 10.0.0.0/16 | depi-sec-private-a | 10.0.11.0/24 | us-east-1a | Private |
| depi-sec-app-vpc | 10.0.0.0/16 | depi-sec-private-b | 10.0.12.0/24 | us-east-1b | Private |
| depi-sec-tools-vpc | 10.1.0.0/16 | depi-sec-tools-a | 10.1.1.0/24 | us-east-1a | Private (peered) |

Full route tables, the traffic-path diagram, and the reasoning behind each placement are in
[`docs/architecture.md`](docs/architecture.md).

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

Full detail, screenshots, and notes on two deliberate deviations are in
[`docs/testing.md`](docs/testing.md). Summary:

| # | Test | Result |
|---|---|---|
| 1 | ALB opened directly | ✅ 403 Forbidden |
| 2 | CloudFront URL opened | ✅ HTTPS, page loads |
| 3 | SSH to a private IP | ✅ Blocked, REJECT logged |
| 4 | RDS from outside the VPC | ✅ No network path (validated via Test 5) |
| 5 | RDS from an app server | ✅ Connects |
| 6 | Make an S3 object public | ✅ Refused |
| 7 | Open SSH 0.0.0.0/0 on a Security Group | ✅ Auto-revoked by Lambda |
| 8 | Stop the web server on one app instance | ✅ Site stays up, alarm fires |
| 9 | Curl an app server from the tools VPC | ✅ Succeeds over peering |
| 10 | Delete a recovery point in a locked vault | ⚠️ Vault lock deliberately not enabled — see note below |

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

### What was not free
Per the project's cost table, three things in this platform are billed by the hour regardless of
Free Tier: the **Application Load Balancer** (~$0.60/day), the **3 VPC interface endpoints**
(~$0.65/day), and — while it existed — the **NAT Gateway was deliberately never created** at all
(VPC endpoints replaced it entirely, at lower cost and without a route to the public internet).
RDS, EFS, and EC2 usage stayed within Free Tier limits (`db.t3.micro`, `t3.micro`, low storage). The
platform was destroyed at the end of every work session per the project's own guidance
("run `terraform destroy` when you stop working") to avoid paying for idle infrastructure overnight.

### Real cost paid
Checked via Billing → Cost Explorer for September 2026 (the month the project was built and torn
down in): **Accrued (actual) cost: $0.00**. Cost Explorer's forecast column showed $12.59, but that
figure projects the month's usage forward as if it continued at the same rate — it does not reflect
reality here, since the infrastructure was destroyed (`terraform destroy`) well before the month
ended and nothing kept running. The $0.00 accrued figure, together with the account's promotional
credit balance, confirms the project stayed within Free Tier / credits for its entire lifetime.

## 10. How to destroy
```bash
cd terraform
terraform destroy
```
Empty both S3 buckets (including old versions) first, or the destroy will fail.

## 11. What I learned

1. **A subnet is public or private purely because of its route table**, not its name or anything
   else — the moment I actually internalized this (Task 4), the rest of the network design made
   much more sense.
2. **Security Groups and NACLs solve different problems.** A Security Group is stateful and only
   needs one inbound rule per direction; a NACL is stateless and needs the return traffic allowed
   explicitly — I only really understood the difference after the ephemeral-port NACL rule silently
   broke SSM connectivity and I had to work out why.
3. **A Gateway Endpoint changes routing, not addresses.** Traffic to S3 through the endpoint still
   arrives from S3's real public IP ranges, so a NACL scoped only to the VPC's own CIDR will quietly
   drop the reply. This one cost real debugging time before the pattern became obvious.
4. **"No SSH, Session-Manager-only" access sounds simple but has real prerequisites**: the right IAM
   role, the right interface endpoints with private DNS enabled, and — something the project brief
   didn't mention — the AMI actually needs the SSM Agent pre-installed. Ours didn't, so nothing
   worked until the agent was installed manually via `user_data`, downloading straight from the
   regional S3 bucket instead of relying on a package manager repository that itself couldn't be
   reached from inside a private subnet.
5. **Package managers assume internet access you might not have.** `dnf`'s default repo mirrorlist
   for this AMI resolved to an S3 "dualstack" hostname that the Gateway Endpoint doesn't cover, which
   broke `nginx` installation entirely. Working around it (fetching the mirrorlist over the working
   hostname and pinning `dnf` to the corrected URL) turned out to be more reliable than avoiding the
   package manager altogether.
6. **CloudTrail and VPC Flow Logs answer different questions.** CloudTrail says who did what on the
   AWS control plane; Flow Logs say what actually crossed the network, regardless of who or what
   caused it. Seeing real, continuous port-scanning traffic get rejected in the Flow Logs made the
   "the internet never stops probing you" idea concrete rather than theoretical.
7. **Reachability Analyzer is powerful but has blind spots** — it couldn't prove a path to AWS's own
   internal DNS resolver (`10.0.0.2`) because that resolver has no visible ENI in the account, which
   looked like a routing failure but was actually a tooling limitation.
8. **Peering is not transitive, and it doesn't just "work."** The tools-vpc needed its own SSM
   endpoints and its own S3 gateway endpoint (peering doesn't share another VPC's endpoints), plus
   explicit Security Group and NACL rules on the app side scoped to the tools subnet specifically.
9. **Not every AWS feature that sounds similar behaves the same way.** I assumed AWS Backup Vault
   Lock had a permission-scoped "governance mode" like S3 Object Lock. It doesn't — every Backup
   vault lock is compliance-style and becomes permanently unremovable once its grace period ends,
   which changed a real decision about whether to use it in a lab account meant to be destroyed.
10. **Automated remediation is genuinely satisfying to see work.** Watching a manually-added
    `0.0.0.0/0:22` rule disappear on its own within about a minute — with no human involved — made the
    detection-vs-remediation distinction from the course material click in a way reading about it
    never did.
11. **Infrastructure as code makes "just try it and see" cheap.** Being able to `terraform destroy`
    and `apply` repeatedly, and to `-replace` a single resource to force it to rebuild, turned what
    would have been terrifying manual Console changes into a normal part of debugging.

## 12. Known limitations

- **No MFA on `depi-dev-1`.** The IAM Console flags this user as "Console access enabled without
  MFA." The account password policy (14 chars, mixed case, number, symbol, 90-day rotation) is
  enforced, but MFA enrollment is a per-user, post-creation action that Terraform cannot fully
  automate for a human user (it can create a virtual MFA device resource, but the user still has to
  scan the QR code and enter two codes interactively). With more time, this would be enforced via an
  IAM policy that denies all actions except `iam:*MFADevice*` and `sts:GetSessionToken` until MFA is
  enabled, rather than left as an unenforced recommendation.
- **AWS Backup Vault Lock is deliberately not enabled.** AWS Backup Vault Lock has no true
  "governance mode" — every lock is compliance-style and becomes permanently unremovable (by anyone,
  including AWS Support) once its short grace period ends. Locking the vault in this lab risked
  leaving a real AWS resource impossible to clean up. The lock was applied briefly to confirm this
  behavior firsthand, then removed while still inside its grace period. Full reasoning is in
  `docs/security-controls.md`. In a real, ongoing production account (not a lab meant to be torn
  down), this lock would be applied deliberately as a ransomware defense.
- **RDS is single-AZ**, per the project's explicit Free Tier guidance — a production deployment would
  use Multi-AZ for automatic failover.
- **The demo "app" is a static page served by Python's `http.server`, not nginx.** The AMI resolved
  by the `most_recent` AMI filter has a broken `dnf` repo mirrorlist path (see "What I learned" #5),
  and while that was worked around for installing the SSM Agent, the web server itself was switched
  to Python to remove that fragile dependency from the critical path. Functionally it satisfies every
  ALB/CloudFront health-check and routing requirement identically to nginx.
- **CloudFront was blocked for several hours by an AWS account-verification requirement** unrelated
  to this code (`AccessDenied: Your account must be verified before you can add new CloudFront
  resources`), resolved via an AWS Support case. This is an account-level restriction on new/Free
  Tier accounts, not a configuration issue, but it did delay Task 13 in this build.
- **No WAF in front of CloudFront.** The secret-header check stops the ALB from being reached
  directly, but it is not a substitute for a real web application firewall against application-layer
  attacks; that was out of scope for this mini project.
- **State is local, not remote.** Per the project's own Task 1 instructions, `terraform.tfstate`
  stays on the operator's machine and is git-ignored. A real team would use an S3 backend with
  DynamoDB state locking instead.
