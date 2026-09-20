# Architecture

_To be completed progressively as the network and services are built (Tasks 4, 7, 12, 13, 18)._

## Diagram
_(add the exported diagram image here once the platform is built)_

## Subnet plan

| Subnet              | CIDR           | AZ           | Type                |
|---------------------|----------------|--------------|---------------------|
| depi-sec-public-a   | 10.0.1.0/24    | us-east-1a   | Public              |
| depi-sec-public-b   | 10.0.2.0/24    | us-east-1b   | Public              |
| depi-sec-private-a  | 10.0.11.0/24   | us-east-1a   | Private             |
| depi-sec-private-b  | 10.0.12.0/24   | us-east-1b   | Private             |
| depi-sec-tools-a    | 10.1.1.0/24    | us-east-1a   | Private (tools VPC) |

## Route tables (Task 4)

**Public route table** (`depi-sec-public-rt`) — associated with `public-a` and `public-b`:
| Destination | Target |
|---|---|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | Internet Gateway (`depi-sec-igw`) |

**Private route table** (`depi-sec-private-rt`) — associated with `private-a` and `private-b`:
| Destination | Target |
|---|---|
| 10.0.0.0/16 | local |

This is the whole difference between "public" and "private" here: the public route table has a
0.0.0.0/0 route to the Internet Gateway, the private one does not. Task 7 adds a route to the S3
gateway endpoint in the private table; Task 18 adds a route to the tools VPC via peering.

## Traffic path (user to database)

```
User browser
   │  HTTPS (443)
   ▼
CloudFront  ──────────────────────  adds secret header X-Origin-Verify
   │  HTTP (80) + X-Origin-Verify header
   ▼
ALB (public subnets)  ── listener default action = 403 Forbidden
   │  only requests carrying the correct X-Origin-Verify header match
   │  the listener rule and get forwarded
   ▼
Target Group → EC2 app servers (private subnets)
   │  mount -t nfs4                    │  mysql (port 3306)
   ▼                                    ▼
EFS (shared files)                RDS MySQL (private subnet)
```

A request that hits the ALB's public DNS name directly (skipping CloudFront) has no
`X-Origin-Verify` header, so it falls through to the listener's default action and gets a
403 — this is Test 1 in Task 20's test plan.
