# Task 5 — Security Groups: the tiered firewall
#
# Each group only accepts traffic from the group above it in the chain.
# depi-sec-alb-sg is the ONLY group open to the whole internet. No group
# anywhere has an inbound rule for port 22.
#
# Groups are declared with no inline ingress/egress blocks; every rule is
# its own aws_vpc_security_group_ingress_rule / _egress_rule resource, as
# required — this also makes referencing another SG's ID (instead of a
# CIDR) straightforward and keeps each rule individually auditable.

# ---------------------------------------------------------------------------
# 1. depi-sec-alb-sg — the only group open to the world
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Internet-facing ALB. Only group open to 0.0.0.0/0."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port            = 80
  ip_protocol        = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_outbound" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound (needed to reach app servers)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# ---------------------------------------------------------------------------
# 2. depi-sec-app-sg — only accepts traffic FROM the ALB security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "App servers. Inbound only from the ALB security group."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.name_prefix}-app-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_http_from_alb" {
  security_group_id           = aws_security_group.app.id
  description                 = "HTTP from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                   = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_all_outbound" {
  security_group_id = aws_security_group.app.id
  description       = "Allow all outbound (SSM, EFS, RDS, S3 endpoint, etc.)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# ---------------------------------------------------------------------------
# 3. depi-sec-db-sg — only accepts MySQL traffic FROM the app security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "RDS MySQL. Inbound only from the app security group."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.name_prefix}-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_mysql_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from app servers only"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 3306
  to_port                       = 3306
  ip_protocol                   = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "db_all_outbound" {
  security_group_id = aws_security_group.db.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# ---------------------------------------------------------------------------
# 4. depi-sec-efs-sg — only accepts NFS traffic FROM the app security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "efs" {
  name        = "${var.name_prefix}-efs-sg"
  description = "EFS mount targets. Inbound only from the app security group."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.name_prefix}-efs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_nfs_from_app" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS from app servers only"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 2049
  to_port                       = 2049
  ip_protocol                   = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "efs_all_outbound" {
  security_group_id = aws_security_group.efs.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# NOTE: No security group in this file has any rule for port 22 (SSH).
# Access to the app servers is by Session Manager only (Tasks 7 & 8).

# ---------------------------------------------------------------------------
# Task 6 — Network ACLs: the second layer
#
# A Security Group is stateful (it remembers the reply automatically). A
# NACL is stateless — the reply must be explicitly allowed on the ephemeral
# port range (1024-65535), or return traffic silently drops.
#
# Rules are evaluated from the lowest rule number to the highest; the first
# match wins and the rest are never read.
# ---------------------------------------------------------------------------
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.app.id
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.name_prefix}-private-nacl"
  }
}

# --- Inbound ---

resource "aws_network_acl_rule" "private_in_100_http" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 80
  to_port         = 80
}

resource "aws_network_acl_rule" "private_in_110_https" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 443
  to_port         = 443
}

resource "aws_network_acl_rule" "private_in_120_ephemeral_return" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port         = 65535
}

# UDP return traffic on the ephemeral range — needed for DNS (UDP 53).
# Without this, TCP-only rule 120 lets outbound DNS queries leave but blocks
# the UDP reply, so hostnames like ssm.us-east-1.amazonaws.com never resolve
# and the SSM Agent can never reach the service — even though the interface
# endpoints and security groups are all correctly configured.
resource "aws_network_acl_rule" "private_in_125_dns_udp_return" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 125
  egress         = false
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port         = 65535
}

resource "aws_network_acl_rule" "private_in_200_deny_ssh" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = 22
  to_port         = 22
}

# --- Task 18: allow the tools-vpc monitoring instance in (HTTP + ICMP) ---
resource "aws_network_acl_rule" "private_in_130_http_from_tools" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.tools_vpc_cidr
  from_port      = 80
  to_port         = 80
}

resource "aws_network_acl_rule" "private_in_135_icmp_from_tools" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 135
  egress         = false
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = var.tools_vpc_cidr
  icmp_type      = -1
  icmp_code      = -1
}

# --- Outbound ---

resource "aws_network_acl_rule" "private_out_100_allow_vpc" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 0
  to_port         = 0
}

# --- Task 18: allow replies back to the tools-vpc monitoring instance ---
resource "aws_network_acl_rule" "private_out_105_allow_tools" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 105
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.tools_vpc_cidr
  from_port      = 0
  to_port         = 0
}

resource "aws_network_acl_rule" "private_out_110_allow_https" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port         = 443
}
