# Testing

The 10 tests from Task 20. Filled in at the end of the project.

| # | Test | Expected result | What happened | Screenshot |
|---|------|------------------|----------------|------------|
| 1 | Open the ALB DNS name directly in a browser | 403 Forbidden | | |
| 2 | Open the CloudFront URL | Page loads over HTTPS | | |
| 3 | Try to SSH to a private instance IP | Timeout + REJECT in Flow Logs | | |
| 4 | Connect to RDS from laptop | Timeout | | |
| 5 | Connect to RDS from app server | Success | | |
| 6 | Make an S3 object public in Console | Refused by Block Public Access | | |
| 7 | Add SSH 0.0.0.0/0 to app SG | Removed by Lambda within a minute, email received | | |
| 8 | Stop nginx on one server | Target unhealthy, site still works, alarm email | | |
| 9 | Curl app server from tools VPC | Page returned | | |
| 10 | Delete a recovery point in the locked vault | Access denied | | |
