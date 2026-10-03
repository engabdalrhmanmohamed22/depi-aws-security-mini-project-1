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

```
                                    INTERNET
                                        │
                                        │ HTTPS (443)
                                        ▼
                              ┌───────────────────┐
                              │    CloudFront      │  adds secret header
                              │  (edge, global)    │  X-Origin-Verify
                              └─────────┬──────────┘
                                        │ HTTP (80) + header
                                        ▼
        ═══════════════════════ depi-sec-app-vpc (10.0.0.0/16) ═══════════════════════
        ║   PUBLIC SUBNETS (route to Internet Gateway)                              ║
        ║   ┌─────────────────────┐        ┌─────────────────────┐                  ║
        ║   │ public-a (10.0.1.0)  │        │ public-b (10.0.2.0)  │  us-east-1a/b   ║
        ║   │   Application Load Balancer (both AZs)                 │              ║
        ║   └──────────┬───────────┘        └──────────┬───────────┘                ║
        ║              │ listener rule: forward only if header matches              ║
        ║   ───────────┼──────────────────────────────┼───────────────────────────  ║
        ║   PRIVATE SUBNETS (no route to internet)                                  ║
        ║              ▼                              ▼                            ║
        ║   ┌─────────────────────┐        ┌─────────────────────┐                  ║
        ║   │ private-a: EC2 app-a │        │ private-b: EC2 app-b │                  ║
        ║   └──────────┬───────────┘        └──────────┬───────────┘                ║
        ║              │  mount -t nfs4                │  mount -t nfs4             ║
        ║              ▼                                ▼                           ║
        ║        EFS (shared /app-data, encrypted)  ── mysql :3306 ──►  RDS MySQL   ║
        ║                                                                            ║
        ║   VPC Endpoints (private subnets): S3 (gateway), SSM/SSMMESSAGES/         ║
        ║   EC2MESSAGES (interface) — management traffic never leaves the VPC       ║
        ║                                                             │ Peering     ║
        ═══════════════════════════════════════════════════════════════│════════════
        ═══════════════════════ depi-sec-tools-vpc (10.1.0.0/16) ══════│════════════
        ║   tools-a (10.1.1.0): EC2 monitor — curls app servers over ──┘            ║
        ║   the peering connection (own SSM endpoints, own S3 gateway endpoint)     ║
        ═══════════════════════════════════════════════════════════════════════════

Account-wide (not tied to one VPC): IAM · Budget + deny-expensive action · CloudTrail
(multi-Region) · VPC Flow Logs · CloudWatch alarms + dashboard · SNS alerts · Lambda
auto-remediation (EventBridge-triggered) · AWS Backup (governance-mode Vault Lock)
```

Full route tables, the traffic-path breakdown, and **why each resource sits where it
sits** are in [`docs/architecture.md`](docs/architecture.md).

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

| # | Control | AWS Service | Threat it stops |
|---|---|---|---|
| 2 | Budget with automatic deny action at 90% | AWS Budgets + IAM | A stolen credential launching expensive resources unnoticed |
| 3 | Password policy, least-privilege group/user/role | IAM | Weak passwords; users or servers with more access than they need |
| 4 | Public/private subnet split via route tables | VPC | Servers being reachable from the internet by default |
| 5 | Tiered Security Groups (ALB → app → db/efs, each referencing the group above it) | EC2 Security Groups | Direct internet access to app servers, database, and file system |
| 6 | Network ACLs (stateless subnet-level backstop) | VPC NACL | Port 22 reachable even if a Security Group were ever misconfigured |
| 7 | VPC Endpoints (S3 gateway + SSM/SSMMESSAGES/EC2MESSAGES interface, no NAT Gateway) | VPC PrivateLink | Needing a NAT Gateway or public IP just to reach AWS services |
| 8 | EC2 with no key pair, no public IP, SSM-only access | EC2 + Systems Manager | Standing SSH access / a leaked key granting a shell |
| 9 | EBS + EFS encryption at rest | KMS (AWS-managed) | Data readable if the underlying disk were ever exposed |
| 10 | S3 Public Access Block, versioning, encryption, HTTPS-only policy | S3 | A bucket or object ever becoming reachable from the internet |
| 11 | Private RDS, encrypted, no public IP, isolated Security Group | RDS | Database reachable from outside the app tier |
| 12 | ALB fronting private app servers, health checks | Elastic Load Balancing | App servers needing a public IP to be reachable at all |
| 13 | CloudFront + secret origin header + ALB default-deny listener | CloudFront + ELB | Bypassing the CDN by hitting the ALB directly |
| 14 | CloudTrail, multi-Region, log file validation, S3 data events | CloudTrail | No record of who did what, or tampered evidence after the fact |
| 15 | VPC Flow Logs (ALL traffic, CloudWatch Logs) | VPC Flow Logs | No visibility into what crossed the network, accepted or rejected |
| 16 | CloudWatch alarms (CPU, ALB health, RDS storage, failed logins) + dashboard | CloudWatch + SNS | Problems or brute-force attempts going unnoticed until too late |
| 17 | Lambda auto-remediation of open SSH/RDP rules | Lambda + EventBridge | A dangerous rule staying open for minutes/hours until a human reacts |
| 18 | VPC peering with least-privilege rules scoped to the monitoring subnet only | VPC Peering | A second trust boundary needing full network access to reach the app |
| 19 | Daily AWS Backup plan, tag-based selection, Vault Lock (governance mode) | AWS Backup | Data loss with no recent recovery point; an attacker deleting backups before destroying data |

Full detail, screenshot references, and design-decision notes (the Security Group chain diagram,
Security Group vs NACL, the Vault Lock governance-mode fix, and the NACL widening for Gateway
Endpoint traffic) are in [`docs/security-controls.md`](docs/security-controls.md).

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

Full detail and screenshots are in [`docs/testing.md`](docs/testing.md). Summary:

| # | Test | Result |
|---|---|---|
| 1 | ALB opened directly | ✅ 403 Forbidden |
| 2 | CloudFront URL opened | ✅ HTTPS, page loads |
| 3 | SSH to a private IP | ✅ Blocked, REJECT logged |
| 4 | RDS from a laptop outside AWS | ✅ Timeout — confirmed unreachable from outside AWS, see `docs/testing.md` |
| 5 | RDS from an app server | ✅ Connects |
| 6 | Make an S3 object public | ✅ Refused |
| 7 | Open SSH 0.0.0.0/0 on a Security Group | ✅ Auto-revoked by Lambda |
| 8 | Stop the web server on one app instance | ✅ Site stays up, alarm fires |
| 9 | Curl an app server from the tools VPC | ✅ Succeeds over peering |
| 10 | Delete a recovery point in the governance-locked vault | ✅ Access Denied — confirmed with the corrected governance-mode Vault Lock, see `docs/testing.md` |

## 8. Screenshots

Grouped under [`screenshots/`](screenshots/) by task number.

| Task | Screenshot | Shows |
|---|---|---|
| 2 | `02-budget/budget-overview.png`, `budget-action.png` | Monthly $10 budget; the 80/90/100% thresholds and deny action |
| 3 | `03-iam/ec2-role-trust-policy.png` | EC2 role trust policy (only `ec2.amazonaws.com` can assume it) |
| 3 | `03-iam/s3-app-read-policy.png` | Custom policy JSON scoped to one bucket |
| 3 | `03-iam/dev1-user-group-only.png` | `depi-dev-1` with zero direct policies |
| 4 | `04-vpc/public-route-table.png` | Public route table (`0.0.0.0/0 → IGW`) |
| 4 | `04-vpc/private-route-table.png` | Private route table (local route only) |
| 4 | `04-vpc/resource-map.png` | Resource map of the 4 subnets across 2 AZs |
| 5 | `05-sg/alb-sg-inbound.png`, `app-sg-inbound.png`, `db-sg-inbound.png`, `efs-sg-inbound.png` | Each Security Group's inbound rules |
| 6 | `06-nacl/nacl-inbound-rules.png`, `nacl-outbound-rules.png` | NACL rule list |
| 7 | `07-endpoints/endpoints-list.png`, `private-route-table-updated.png` | VPC endpoints and the resulting route |
| 8 | `08-ec2-ssm/session-manager-shell.png`, `no-public-ip.png`, `ssm-connect.png` | SSM shell access, empty public-IP field, connect screen |
| 9 | `09-efs/efs-shared-file.png`, `efs-shared-file-test.png`, `encrypted-volume-1.png`, `encrypted-volume-2.png` | Shared file visible from both servers; encrypted EBS volumes |
| 10 | `10-s3/public-access-block.png`, `public-access-refused.png` | Block Public Access on; a "make public" attempt refused |
| 11 | `11-rds/rds-connectivity.png`, `connection-success-from-inside.png`, `timeout-from-laptop.png` | RDS not publicly accessible; success from inside; confirmed timeout when reached from outside AWS |
| 12 | `12-alb/healthy-targets.png`, `unhealthy-target.png`, `stop.png`, `test-before-stop.png`, `test-after-stop.png` | Healthy/unhealthy targets; site staying up after stopping one server |
| 13 | `13-cloudfront/cloudfront-https-works.png`, `alb-direct-403.png` | CloudFront over HTTPS vs. the ALB's 403 |
| 14 | `14-cloudtrail/trail-settings.png`, `event-with-identity.png`, `describetrail.png` | Trail settings; an event showing identity/IP/time |
| 15 | `15-flowlogs/reject-record.png` | A REJECT record from VPC Flow Logs |
| 16 | `16-cloudwatch/dashboard.png`, `alarm-in-alarm-state.png`, `alert-email.png` | Dashboard; an alarm firing; the alert email |
| 17 | `17-lambda/rule-added.png`, `rule-removed.png`, `lambda-logs.png` | Rule added, then auto-removed; Lambda execution log |
| 18 | `18-peering/peering-route-1.png`, `peering-route-2.png`, `successful-curl.png`, `test.png` | Peering routes on both sides; successful curl across the peering connection |
| 19 | `19-backup/vault-created.png`, `backup-plan.png`, `completed-job.png`, `locked-vault.png`, `delete-refused.png` | Vault, plan, and a completed backup job; vault locked in governance mode; delete attempt refused |
| 20 | `20-testing-destroy/ec2-empty.png`, `vpc-empty.png`, `rds-empty.png` | Empty console after `terraform destroy` |

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
Per the project's cost table, two things in this platform are billed by the hour regardless of Free
Tier: the **Application Load Balancer** (approximately $0.60/day) and the **3 VPC interface
endpoints** (approximately $0.65/day). A NAT Gateway was never created — the VPC endpoints replace it
entirely, at lower cost and without giving the private subnets a route to the public internet. RDS,
EFS, and EC2 usage stayed within Free Tier limits (`db.t3.micro`, `t3.micro`, low storage). The
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
9. **Reading AWS's own parameter semantics carefully matters more than pattern-matching to a
   similar-sounding feature.** I initially assumed AWS Backup Vault Lock had no permission-scoped
   "governance mode" like S3 Object Lock, because testing it with `changeable_for_days` set showed a
   "Compliance lock in grace time" label — and wrongly generalized from that one configuration to
   "the whole feature." The actual rule is precise: omitting `changeable_for_days` entirely gives true
   governance mode (permanent, but bypassable by an authorized principal); setting it gives compliance
   mode (temporarily editable, then permanently unremovable by anyone). The fix was one line removed,
   not disabling the control.
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
- **AWS Backup Vault Lock is enabled in governance mode**, not compliance mode: `changeable_for_days`
  is intentionally omitted from `aws_backup_vault_lock_configuration`, which is what selects
  governance mode (permanent lock, but bypassable by a principal with
  `backup:BypassGovernanceRetention`) rather than compliance mode (temporarily editable, then
  permanently unremovable by anyone, including AWS Support). An earlier draft of this project
  mistakenly disabled the lock entirely based on a misreading of this parameter — corrected in
  `docs/security-controls.md`.
- **RDS is single-AZ**, per the project's explicit Free Tier guidance — a production deployment would
  use Multi-AZ for automatic failover.
- **The AMI resolved by the `most_recent` filter does not ship with the SSM Agent or a working `dnf`
  repo mirrorlist out of the box.** Both were fixed in `user_data`: the SSM Agent is installed
  directly from the regional S3 bucket, and `dnf` is pinned to a corrected (non-dualstack) mirror URL
  so that `nginx` and `nfs-utils` install normally. See "What I learned" #4 and #5 for the full story.
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
