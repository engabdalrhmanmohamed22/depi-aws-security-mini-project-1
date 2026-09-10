# ---------------------------------------------------------------------------
# Task 5 - Security Groups: a tiered firewall.
#
# Each group only allows traffic from the group above it in the chain:
#   Internet -> alb-sg -> app-sg -> db-sg / efs-sg
#
# We reference security group IDs as sources instead of CIDR blocks.
# A CIDR stops being correct the day a subnet changes. A group reference
# follows the instances wherever they move, so the rule stays true.
#
# No group anywhere has an inbound rule for port 22 (SSH). Access is only
# via Session Manager, configured in Task 8.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. ALB security group - the ONLY group open to the whole internet
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allows inbound HTTP from the internet. The only SG open to 0.0.0.0/0."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  description        = "HTTP from anywhere - CloudFront and direct testing"
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "tcp"
  from_port          = 80
  to_port            = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_all_outbound" {
  security_group_id = aws_security_group.alb.id
  description        = "ALB needs to reach the app servers on any port/protocol"
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# ---------------------------------------------------------------------------
# 2. App server security group - only reachable from the ALB
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allows inbound HTTP only from the ALB security group."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_http_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                   = "HTTP from the ALB only - not from a CIDR"
  referenced_security_group_id  = aws_security_group.alb.id
  ip_protocol                   = "tcp"
  from_port                     = 80
  to_port                       = 80
}

resource "aws_vpc_security_group_egress_rule" "app_all_outbound" {
  security_group_id = aws_security_group.app.id
  description        = "App servers need to reach RDS, EFS, and AWS endpoints"
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# ---------------------------------------------------------------------------
# 3. Database security group - only reachable from the app servers
# ---------------------------------------------------------------------------

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allows inbound MySQL only from the app security group."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_mysql_from_app" {
  security_group_id            = aws_security_group.db.id
  description                   = "MySQL from the app servers only"
  referenced_security_group_id  = aws_security_group.app.id
  ip_protocol                   = "tcp"
  from_port                     = 3306
  to_port                       = 3306
}

resource "aws_vpc_security_group_egress_rule" "db_all_outbound" {
  security_group_id = aws_security_group.db.id
  description        = "Default outbound - kept open for engine updates"
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# ---------------------------------------------------------------------------
# 4. EFS security group - only reachable from the app servers
# ---------------------------------------------------------------------------

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "Allows inbound NFS only from the app security group."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-efs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_nfs_from_app" {
  security_group_id            = aws_security_group.efs.id
  description                   = "NFS (2049) from the app servers only"
  referenced_security_group_id  = aws_security_group.app.id
  ip_protocol                   = "tcp"
  from_port                     = 2049
  to_port                       = 2049
}

resource "aws_vpc_security_group_egress_rule" "efs_all_outbound" {
  security_group_id = aws_security_group.efs.id
  description        = "Default outbound"
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
}
