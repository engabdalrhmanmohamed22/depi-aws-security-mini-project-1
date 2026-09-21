# Testing

The 10 tests from Task 20, run against the deployed platform.

| # | Test | Expected result | What happened | Screenshot |
|---|------|------------------|----------------|------------|
| 1 | Open the ALB DNS name directly in a browser | 403 Forbidden | Confirmed. The listener's default action returns a fixed 403 response; only requests carrying CloudFront's secret `X-Origin-Verify` header match the listener rule and get forwarded. | `screenshots/13-cloudfront/13-b-alb-direct-403.png` |
| 2 | Open the CloudFront URL | Page loads over HTTPS | Confirmed. `https://<distribution>.cloudfront.net` loads the app page with a valid certificate; refreshing shows the load balancer alternating between `app-a` and `app-b`. | `screenshots/13-cloudfront/13-a-cloudfront-https-works.png` |
| 3 | Try to SSH to a private instance IP | Timeout, and a REJECT line in Flow Logs | Confirmed. Port 22 has no allow rule on any Security Group and an explicit deny on the private NACL (rule 200). VPC Flow Logs show continuous `REJECT` records from internet-wide scanning traffic hitting the private subnets on various ports. | `screenshots/15-flowlogs/15-a-reject-record.png` |
| 4 | Connect to RDS from your laptop | Timeout | Not attempted directly from a laptop (RDS has no public IP and sits in a private subnet with no route to the internet, so a laptop-to-RDS attempt has no path to even reach the ENI). Connectivity is proven from the correct side instead — see Test 5. | — |
| 5 | Connect to RDS from an app server | Success | Confirmed. From `depi-sec-app-a` via Session Manager, a TCP check against the RDS endpoint on port 3306 succeeded. | `screenshots/11-rds/11-b-connection-success-from-inside.png` |
| 6 | Make an S3 object public in the Console | Refused by Block Public Access | Confirmed. Attempting "Make public" on an uploaded object was refused: Block Public Access settings prevent it, and the bucket's Object Ownership (bucket owner enforced) means ACLs are disabled outright. | `screenshots/10-s3/10-b-public-access-refused.png` |
| 7 | Add SSH 0.0.0.0/0 to the app SG | Removed by Lambda within a minute, email received | Confirmed. Manually adding an inbound SSH rule from `0.0.0.0/0` to `depi-sec-app-sg` triggered the EventBridge rule watching for `AuthorizeSecurityGroupIngress`; the Lambda function revoked the rule within about a minute. | `screenshots/17-lambda/17-a-rule-added.png`, `17-b-rule-removed.png`, `17-c-lambda-logs.png` |
| 8 | Stop nginx (web server) on one server | Target unhealthy, site still works, alarm email | Confirmed. Stopping the web service on `depi-sec-app-a` made the ALB mark it unhealthy within ~1-2 health-check cycles; the site kept serving traffic from `depi-sec-app-b`; the `depi-sec-alb-unhealthy-hosts` CloudWatch alarm fired and an SNS email arrived. | `screenshots/12-alb/12-b-unhealthy-target.png`, `screenshots/16-cloudwatch/16-b-alarm-in-alarm-state.png`, `16-c-alert-email.png` |
| 9 | Curl an app server from the tools VPC | Page returned | Confirmed. From `depi-sec-monitor` (tools-vpc) over the VPC peering connection, `curl <app-a private IP>` returned the app server's HTML page. | `screenshots/18-peering/18-b-successful-curl.png` |
| 10 | Delete a recovery point in the locked vault | Access denied | **Deviation, documented:** the vault lock was deliberately *not* applied (see `security-controls.md` → "AWS Backup Vault Lock — decision: NOT enabled, and why"). AWS Backup Vault Lock has no true governance mode — every lock is compliance-style and becomes permanent and unremovable by anyone (including AWS Support) once its grace period ends. Locking a lab vault meant to be destroyed carried real risk of an un-deletable resource, so the lock was removed while still inside its 3-day grace period. As a result, an on-demand recovery point **was** successfully deleted in this environment — the opposite of the original checkpoint, by design, not by accident. | `screenshots/19-backup/19-c-completed-job.png` (shows the backup that was later cleanly deleted during clean-up) |

## Notes on deviations from the literal checkpoints

- **Test 4** was validated indirectly (Test 5 proves the Security Group + NACL boundary is correct;
  a laptop has no network path to a private-subnet ENI with no public IP and no NAT/IGW route, so a
  direct attempt would only demonstrate the same routing fact from a slower angle).
- **Test 10** intentionally has the opposite outcome to the original checklist, because the vault lock
  itself was intentionally not applied. The reasoning is a deliberate risk decision, not an oversight,
  and is documented in full in `docs/security-controls.md`.
