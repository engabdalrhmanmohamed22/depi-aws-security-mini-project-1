# Architecture

## Traffic path (user to database)

```
Internet users
   |
   v
[ CloudFront ]              <- caching + HTTPS front door
   | (secret header)
   v
[ Application Load Balancer ] <- public subnets
   |
   +---------------+---------------+
   v                               v
[ EC2 app server ]          [ EC2 app server ]  <- private subnets
   AZ-a                        AZ-b
   |                               |
   +--------+-------+--------------+
            |       |
            v       v
        [ RDS ]  [ EFS ]           <- private subnets
        MySQL    shared files
```

No public IP on the app servers. No SSH key. Access only by Session Manager.

## Network design table (Task 4)

| VPC | CIDR | Purpose |
|---|---|---|
| `depi-sec-app-vpc` | 10.0.0.0/16 | Main network — web servers, database, file share |
| `depi-sec-tools-vpc` (Task 18) | 10.1.0.0/16 | Monitoring server, reached privately via VPC peering |

| Subnet | CIDR | AZ | Type | What lives there |
|---|---|---|---|---|
| `depi-sec-public-a` | 10.0.1.0/24 | us-east-1a | Public | Load balancer |
| `depi-sec-public-b` | 10.0.2.0/24 | us-east-1b | Public | Load balancer |
| `depi-sec-private-a` | 10.0.11.0/24 | us-east-1a | Private | EC2, RDS, EFS |
| `depi-sec-private-b` | 10.0.12.0/24 | us-east-1b | Private | EC2, RDS, EFS |
| `depi-sec-tools-a` (Task 18) | 10.1.1.0/24 | us-east-1a | Private (tools VPC) | Monitoring instance |

## Why each resource sits where it sits

- **Public subnets** hold only the Application Load Balancer. The ALB is the
  single entry point from the internet — nothing else is exposed.
- **Private subnets** hold the EC2 app servers, the RDS database, and the EFS
  file system. None of them have a route to the internet, and none of them
  have a public IP.
- **Two Availability Zones** (`us-east-1a`, `us-east-1b`) mean the platform
  survives the loss of one data centre. Every tier (ALB, EC2, RDS via subnet
  group) is spread across both AZs.

## Route tables

| Route table | Routes | Associated with |
|---|---|---|
| Public route table | `0.0.0.0/0` → Internet Gateway | public-a, public-b |
| Private route table | (local only, initially) | private-a, private-b |

**The rule to remember:** a subnet is not public because of its name. A
subnet is public because its route table has a route to an Internet
Gateway. That is the only real difference between "public" and "private"
here.

The private route table gains additional routes in later tasks:
- Task 7 — a route to the S3 gateway VPC endpoint (`pl-xxxxxx`)
- Task 18 — a route to the tools VPC via VPC peering (`10.1.0.0/16`)
