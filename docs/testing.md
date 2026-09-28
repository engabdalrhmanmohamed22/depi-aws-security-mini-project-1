# Testing

The 10 tests from Task 20, run against the deployed platform.

| # | Test | Expected result | What happened | Screenshot |
|---|------|------------------|----------------|------------|
| 1 | Open the ALB DNS name directly in a browser | 403 Forbidden | Confirmed. The listener's default action returns a fixed 403 response; only requests carrying CloudFront's secret `X-Origin-Verify` header match the listener rule and get forwarded. | `screenshots/13-cloudfront/13-b-alb-direct-403.png` |
| 2 | Open the CloudFront URL | Page loads over HTTPS | Confirmed. `https://<distribution>.cloudfront.net` loads the app page with a valid certificate; refreshing shows the load balancer alternating between `app-a` and `app-b`. | `screenshots/13-cloudfront/13-a-cloudfront-https-works.png` |
| 3 | Try to SSH to a private instance IP | Timeout, and a REJECT line in Flow Logs | Confirmed. Port 22 has no allow rule on any Security Group and an explicit deny on the private NACL (rule 200). VPC Flow Logs show continuous `REJECT` records from internet-wide scanning traffic hitting the private subnets on various ports. | `screenshots/15-flowlogs/15-a-reject-record.png` |
| 4 | Connect to RDS from your laptop | Timeout | **Action required before submission:** run `nc -zv <rds-endpoint> 3306` (or `Test-NetConnection -ComputerName <rds-endpoint> -Port 3306` on Windows) from your own laptop, on your normal home/office network — not from inside any AWS resource. RDS has no public IP and sits in a private subnet with no route to the internet, so this should hang and time out. Take a screenshot of the timeout and replace this row. | `screenshots/11-rds/11-c-timeout-from-laptop.png` *(capture this before submitting)* |
| 5 | Connect to RDS from an app server | Success | Confirmed. From `depi-sec-app-a` via Session Manager, a TCP check against the RDS endpoint on port 3306 succeeded. | `screenshots/11-rds/11-b-connection-success-from-inside.png` |
| 6 | Make an S3 object public in the Console | Refused by Block Public Access | Confirmed. Attempting "Make public" on an uploaded object was refused: Block Public Access settings prevent it, and the bucket's Object Ownership (bucket owner enforced) means ACLs are disabled outright. | `screenshots/10-s3/10-b-public-access-refused.png` |
| 7 | Add SSH 0.0.0.0/0 to the app SG | Removed by Lambda within a minute, email received | Confirmed. Manually adding an inbound SSH rule from `0.0.0.0/0` to `depi-sec-app-sg` triggered the EventBridge rule watching for `AuthorizeSecurityGroupIngress`; the Lambda function revoked the rule within about a minute. | `screenshots/17-lambda/17-a-rule-added.png`, `17-b-rule-removed.png`, `17-c-lambda-logs.png` |
| 8 | Stop nginx on one server | Target unhealthy, site still works, alarm email | Confirmed. Stopping nginx on `depi-sec-app-a` made the ALB mark it unhealthy within ~1-2 health-check cycles; the site kept serving traffic from `depi-sec-app-b`; the `depi-sec-alb-unhealthy-hosts` CloudWatch alarm fired and an SNS email arrived. | `screenshots/12-alb/12-b-unhealthy-target.png`, `screenshots/16-cloudwatch/16-b-alarm-in-alarm-state.png`, `16-c-alert-email.png` |
| 9 | Curl an app server from the tools VPC | Page returned | Confirmed. From `depi-sec-monitor` (tools-vpc) over the VPC peering connection, `curl <app-a private IP>` returned the app server's HTML page. | `screenshots/18-peering/18-b-successful-curl.png` |
| 10 | Delete a recovery point in the locked vault | Access denied | **Action required before submission:** the vault lock is now correctly configured in **governance mode** (see `security-controls.md` — the earlier "no governance mode exists" claim was a mistake; simply omitting `changeable_for_days` gives true governance mode). After `terraform apply`, create an on-demand backup, wait for it to complete, then attempt to delete that recovery point **as the `depi-dev-1` user or any principal without `backup:BypassGovernanceRetention`**. Expected result: refused with an access-denied error. Take a screenshot and replace this row. | `screenshots/19-backup/19-d-delete-refused.png` *(capture this before submitting)* |

## Notes on deviations from the literal checkpoints

- **Test 4** must be a real attempt from outside AWS (a home/office laptop), not inferred from Test 5.
  A previous version of this document incorrectly treated Test 5's success as indirect proof of Test
  4 — that only confirms the Security Group and NACL are correctly scoped, not that an external
  network path was actually tried and timed out. Both are now required and distinct.
- **Test 10** now uses the corrected governance-mode Vault Lock (see `security-controls.md`). An
  earlier version of this project mistakenly removed the lock entirely based on an incorrect claim
  that AWS Backup has no governance mode; the real fix was to omit `changeable_for_days`, not to skip
  locking altogether.
