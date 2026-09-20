# Task 7 — VPC endpoints: private access to AWS services with NO internet route
#
# This is what makes Session Manager work on servers that have no public IP
# and sit behind a route table with no route to the internet at all.

# ---------------------------------------------------------------------------
# 1. Gateway endpoint for S3 — a route in the private route table, free.
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.app.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.name_prefix}-s3-endpoint"
  }
}

# ---------------------------------------------------------------------------
# 2. Security group for the interface endpoints — HTTPS from inside the VPC
# ---------------------------------------------------------------------------
resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-endpoint-sg"
  description = "Interface VPC endpoints. Inbound HTTPS from inside the VPC only."
  vpc_id      = aws_vpc.app.id

  tags = {
    Name = "${var.name_prefix}-endpoint-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https_from_vpc" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port            = 443
  ip_protocol        = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "endpoints_all_outbound" {
  security_group_id = aws_security_group.endpoints.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# ---------------------------------------------------------------------------
# 3. Interface endpoints — SSM, SSM Messages, EC2 Messages.
#    Private DNS enabled on all three is what lets the SSM Agent on the
#    instance resolve the normal AWS service hostnames to a private IP
#    inside the VPC instead of failing to reach the internet.
# ---------------------------------------------------------------------------
locals {
  interface_endpoint_services = ["ssm", "ssmmessages", "ec2messages"]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoint_services)

  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-${each.value}-endpoint"
  }
}
