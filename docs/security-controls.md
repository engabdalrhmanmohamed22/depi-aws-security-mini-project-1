# Security Controls

One row per control, covering every task in the project.

| # | Control | AWS Service | Threat it stops | Screenshot |
|---|---|---|---|---|
| 2 | Budget with automatic deny action at 90% | AWS Budgets + IAM | A stolen credential launching expensive resources unnoticed | `screenshots/02-budget/02-a-budget-overview.png`, `02-b-budget-action.png` |
| 3 | Password policy, least-privilege group/user/role | IAM | Weak passwords; users or servers with more access than they need | `screenshots/03-iam/03-a-ec2-role-trust-policy.png`, `03-b-s3-app-read-policy.png`, `03-c-dev1-user-group-only.png` |
| 4 | Public/private subnet split via route tables | VPC | Servers being reachable from the internet by default | `screenshots/04-vpc/04-a-public-route-table.png`, `04-b-private-route-table.png`, `04-c-resource-map.png` |
| 5 | Tiered Security Groups (chain below) | EC2 Security Groups | Direct internet access to app servers, database, and file system | `screenshots/05-sg/05-a-alb-sg-inbound.png` … `05-d-efs-sg-inbound.png` |
| 6 | Network ACLs (stateless subnet-level backstop) | VPC NACL | Port 22 reachable even if a Security Group were ever misconfigured | `screenshots/06-nacl/06-a-nacl-inbound-rules.png`, `06-b-nacl-outbound-rules.png` |
| 7 | VPC Endpoints (S3 gateway + SSM/SSMMESSAGES/EC2MESSAGES interface) | VPC PrivateLink | Needing a NAT Gateway or public IP just to reach AWS services | `screenshots/07-endpoints/07-a-endpoints-list.png`, `07-b-private-route-table-updated.png` |
| 8 | EC2 with no key pair, no public IP, SSM-only access | EC2 + Systems Manager | Standing SSH access / a leaked key granting a shell | `screenshots/08-ec2-ssm/08-a-session-manager-shell.png`, `08-b-no-public-ip.png` |
| 9 | EBS + EFS encryption at rest | KMS (AWS-managed) | Data readable if the underlying disk were ever exposed | `screenshots/09-efs/09-a-efs-shared-file.png`, `09-b-encrypted-volumes.png` |
| 10 | S3 Public Access Block, versioning, encryption, HTTPS-only policy | S3 | A bucket or object ever becoming reachable from the internet | `screenshots/10-s3/10-a-public-access-block.png`, `10-b-public-access-refused.png` |
| 11 | Private RDS, encrypted, no public IP, isolated Security Group | RDS | Database reachable from outside the app tier | `screenshots/11-rds/11-a-rds-connectivity.png`, `11-b-connection-success-from-inside.png` |
| 12 | ALB fronting private app servers, health checks | Elastic Load Balancing | App servers needing a public IP to be reachable at all | `screenshots/12-alb/12-a-healthy-targets.png`, `12-b-unhealthy-target.png`, `12-c-working-page.png` |
| 13 | CloudFront + secret origin header + ALB default-deny listener | CloudFront + ELB | Bypassing the CDN/WAF layer by hitting the ALB directly | `screenshots/13-cloudfront/13-a-cloudfront-https-works.png`, `13-b-alb-direct-403.png` |
| 14 | CloudTrail, multi-Region, log file validation, S3 data events | CloudTrail | No record of who did what, or tampered evidence after the fact | `screenshots/14-cloudtrail/14-a-trail-settings.png`, `14-b-event-with-identity.png` |
| 15 | VPC Flow Logs (ALL traffic, CloudWatch Logs) | VPC Flow Logs | No visibility into what crossed the network, accepted or rejected | `screenshots/15-flowlogs/15-a-reject-record.png` |
| 16 | CloudWatch alarms (CPU, ALB health, RDS storage, failed logins) + dashboard | CloudWatch + SNS | Problems or brute-force attempts going unnoticed until too late | `screenshots/16-cloudwatch/16-a-dashboard.png`, `16-b-alarm-in-alarm-state.png`, `16-c-alert-email.png` |
| 17 | Lambda auto-remediation of open SSH/RDP rules | Lambda + EventBridge | A dangerous rule staying open for minutes/hours until a human reacts | `screenshots/17-lambda/17-a-rule-added.png`, `17-b-rule-removed.png`, `17-c-lambda-logs.png` |
| 18 | VPC peering with least-privilege rules for the monitoring subnet only | VPC Peering | A second trust boundary (ops/monitoring) needing full network access to reach the app | `screenshots/18-peering/18-a-peering-routes.png`, `18-b-successful-curl.png` |
| 19 | Daily AWS Backup plan, tag-based selection | AWS Backup | Data loss with no recent recovery point | `screenshots/19-backup/19-a-vault-created.png`, `19-b-backup-plan.png`, `19-c-completed-job.png` |

## Security Group chain (Task 5)

```
Internet (0.0.0.0/0)
      │  TCP 80
      ▼
depi-sec-alb-sg   ← the ONLY group open to the world
      │  TCP 80  (source = alb-sg, not a CIDR)
      ▼
depi-sec-app-sg   ← app servers
      │                              │
      │ TCP 3306 (source = app-sg)   │ TCP 2049 (source = app-sg)
      ▼                              ▼
depi-sec-db-sg                 depi-sec-efs-sg
(RDS MySQL)                    (EFS mount targets)
```

No group in this chain has an inbound rule for port 22. Every rule below the ALB references
another security group's ID rather than a CIDR block, so the rule keeps working even if a subnet
is resized or an instance moves to a different subnet later.

## Security Group vs NACL (Task 6)

A Security Group is **stateful**: it automatically allows the reply to traffic it already let in, so
one inbound rule is enough for a full request/response. A Network ACL is **stateless**: it evaluates
every packet independently, so the *return* traffic must be explicitly allowed too — which is why the
private NACL has a rule allowing inbound TCP 1024-65535 (the ephemeral port range), even though
nothing ever "asks" for that traffic on purpose. NACLs are also evaluated by rule number, lowest
first, with the first match winning — a subnet-level backstop that still blocks port 22 even if a
Security Group were ever misconfigured to allow it.

### Deviation from the literal spec: ephemeral-return CIDR widened to 0.0.0.0/0
The original design scoped the TCP ephemeral-return rule (120) to `10.0.0.0/16` only. In testing,
this blocked traffic through the **S3 Gateway Endpoint** (Task 7): a Gateway Endpoint only changes
routing — it does NOT rewrite packet source/destination addresses — so responses from S3 arrive from
S3's real public IP ranges, not from an address inside the VPC CIDR. The stateless NACL was rejecting
that inbound return traffic. The rule was widened to `0.0.0.0/0` for TCP ephemeral ports so any AWS
service reached through the Gateway Endpoint (or a future NAT-based path) can complete its response.
This does not reopen any inbound port to the internet — only established outbound connections get a
matching ephemeral-port reply — and port 22 stays explicitly denied by rule 200 regardless.

## S3 bucket controls (Task 10)

| Control | Applies to | Threat it stops |
|---|---|---|
| Public Access Block (all 4 settings) | Both buckets | Bucket or objects ever becoming reachable from the internet |
| Versioning | Both buckets | Accidental overwrite/delete loses data permanently |
| Default encryption (SSE-S3) | Both buckets | Data at rest readable if the underlying storage were ever exposed |
| Deny-insecure-transport bucket policy | Both buckets | Credentials/data readable in transit over plain HTTP |
| Lifecycle (noncurrent → Glacier at 30d, expire at 365d) | Both buckets | Unbounded storage cost from old versions piling up forever |

Bucket policy (both buckets use the same shape, only the ARN differs):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::BUCKET_NAME", "arn:aws:s3:::BUCKET_NAME/*"],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

**Public Access Block vs IAM — important distinction:** Block Public Access only stops the *bucket*
from becoming reachable from the internet. It does **not** restrict what an authenticated IAM
identity inside the account can do — that boundary is enforced separately by IAM policy (see the
`depi-sec-s3-app-read` policy in Task 3, scoped to `s3:GetObject` on the app bucket only).

## VPC Flow Log fields (Task 15)

The filter pattern used to find rejected SSH attempts:
```
[version, account, eni, source, destination, srcport, destport="22", protocol, packets, bytes, start, end, action="REJECT", status]
```

| Field | Meaning |
|---|---|
| `version` | Flow log record format version |
| `account` | AWS account ID that owns the ENI |
| `eni` | Elastic Network Interface ID the traffic crossed |
| `source` / `destination` | Source and destination IP addresses |
| `srcport` / `destport` | Source and destination ports (filtered on `destport=22` here) |
| `protocol` | IANA protocol number (6 = TCP) |
| `packets` / `bytes` | Size of the flow |
| `start` / `end` | Unix timestamps for the capture window |
| `action` | `ACCEPT` or `REJECT` — filtered on `REJECT` here |
| `status` | Whether the flow log itself was captured OK (`OK`, `NODATA`, `SKIPDATA`) |



## AWS Backup Vault Lock (Task 19) — decision: NOT enabled, and why

AWS Backup Vault Lock does **not** have a persistent "governance mode" the way S3 Object Lock does.
Every vault lock is inherently a compliance-style lock: AWS gives an editable grace period
(`changeable_for_days`, capped at 3 days) during which the lock can still be removed, but once that
window closes the lock becomes **permanent — unremovable by anyone, including the root user and AWS
Support** — for the entire retention period (up to 365 days here).

This was confirmed hands-on: enabling the lock in this lab showed the console label
**"Compliance lock in grace time"**, not "Governance." Since the project brief explicitly warns
against ever using compliance mode in a learning account ("Compliance mode cannot be removed by
anybody, including AWS Support, until the lock expires"), and Backup Vault Lock offers no other mode,
**the lock configuration was deliberately removed while still inside its 3-day grace period**, before
it could become permanent. The vault, the daily backup plan (30-day retention), and the tag-based
selection are all still in place and satisfy the rest of Task 19 — only the irreversible lock itself
was left out, as a documented, deliberate risk decision rather than an oversight.

**In a real production environment** (not a lab meant to be destroyed), this lock would typically be
enabled deliberately as a ransomware defense, accepting the permanence as the whole point of the
control — that trade-off only makes sense once the retention policy has been reviewed and approved by
someone accountable for it, which is not the case for a mini-project meant to be torn down.
