# Task 18 — Second VPC (tools) + VPC peering
#
# A monitoring server in its own small VPC reaches the app servers
# privately, over a peering connection — no internet involved either side.

# ---------------------------------------------------------------------------
# tools-vpc — one private subnet, its own SSM interface endpoints (a peered
# VPC does not automatically share the app-vpc's private DNS for those
# endpoints, so tools-vpc gets its own — same pattern as Task 7).
# ---------------------------------------------------------------------------
resource "aws_vpc" "tools" {
  cidr_block           = var.tools_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-tools-vpc"
  }
}

resource "aws_subnet" "tools_a" {
  vpc_id                  = aws_vpc.tools.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-tools-a"
  }
}

resource "aws_route_table" "tools" {
  vpc_id = aws_vpc.tools.id

  tags = {
    Name = "${var.name_prefix}-tools-rt"
  }
}

resource "aws_route_table_association" "tools_a" {
  subnet_id      = aws_subnet.tools_a.id
  route_table_id = aws_route_table.tools.id
}

# S3 Gateway Endpoint for tools-vpc — needed so the monitoring instance can
# download the SSM Agent from S3, same reason app-vpc has one (Task 7).
resource "aws_vpc_endpoint" "tools_s3" {
  vpc_id            = aws_vpc.tools.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.tools.id]

  tags = {
    Name = "${var.name_prefix}-tools-s3-endpoint"
  }
}

# ---------------------------------------------------------------------------
# Peering connection — app-vpc initiates, auto-accepted (same account).
# ---------------------------------------------------------------------------
resource "aws_vpc_peering_connection" "app_to_tools" {
  vpc_id      = aws_vpc.app.id
  peer_vpc_id = aws_vpc.tools.id
  auto_accept = true

  tags = {
    Name = "${var.name_prefix}-app-to-tools"
  }
}

# Both sides need a route — peering is not transitive, and each VPC only
# knows about the other's CIDR through an explicit route.
resource "aws_route" "app_private_to_tools" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = var.tools_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_to_tools.id
}

resource "aws_route" "tools_to_app" {
  route_table_id            = aws_route_table.tools.id
  destination_cidr_block    = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_to_tools.id
}

# ---------------------------------------------------------------------------
# Let the monitoring server reach the app servers: ICMP + HTTP from the
# tools subnet only.
# ---------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "app_http_from_tools" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP from the tools VPC monitoring subnet"
  cidr_ipv4         = "10.1.1.0/24"
  from_port         = 80
  to_port            = 80
  ip_protocol        = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_icmp_from_tools" {
  security_group_id = aws_security_group.app.id
  description       = "ICMP (ping) from the tools VPC monitoring subnet"
  cidr_ipv4         = "10.1.1.0/24"
  ip_protocol        = "icmp"
  from_port          = -1
  to_port             = -1
}

# ---------------------------------------------------------------------------
# tools-vpc's own SSM interface endpoints, so the monitoring instance can
# be managed the same way as the app servers — no SSH, no public IP.
# ---------------------------------------------------------------------------
resource "aws_security_group" "tools_endpoints" {
  name        = "${var.name_prefix}-tools-endpoint-sg"
  description = "Interface VPC endpoints in tools-vpc. Inbound HTTPS from inside tools-vpc only."
  vpc_id      = aws_vpc.tools.id

  tags = {
    Name = "${var.name_prefix}-tools-endpoint-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "tools_endpoints_https" {
  security_group_id = aws_security_group.tools_endpoints.id
  description       = "HTTPS from inside tools-vpc"
  cidr_ipv4         = var.tools_vpc_cidr
  from_port         = 443
  to_port            = 443
  ip_protocol        = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "tools_endpoints_all_outbound" {
  security_group_id = aws_security_group.tools_endpoints.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol        = "-1"
}

resource "aws_vpc_endpoint" "tools_interface" {
  for_each = toset(local.interface_endpoint_services)

  vpc_id              = aws_vpc.tools.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.tools_a.id]
  security_group_ids  = [aws_security_group.tools_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-tools-${each.value}-endpoint"
  }
}

# ---------------------------------------------------------------------------
# The monitoring instance itself — same role, same "no key, no public IP"
# design as the app servers.
# ---------------------------------------------------------------------------
resource "aws_security_group" "monitor" {
  name        = "${var.name_prefix}-monitor-sg"
  description = "Monitoring instance in tools-vpc. No inbound needed."
  vpc_id      = aws_vpc.tools.id

  tags = {
    Name = "${var.name_prefix}-monitor-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "monitor_all_outbound" {
  security_group_id = aws_security_group.monitor.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol        = "-1"
}

resource "aws_instance" "monitor" {
  ami                          = data.aws_ami.amazon_linux_2023.id
  instance_type                = "t3.micro"
  subnet_id                    = aws_subnet.tools_a.id
  vpc_security_group_ids       = [aws_security_group.monitor.id]
  iam_instance_profile         = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address  = false
  user_data_replace_on_change  = true
  # No key_name — Session Manager only, same as the app servers.

  user_data = <<-EOF
    #!/bin/bash
    curl -s -o /tmp/amazon-ssm-agent.rpm https://s3.us-east-1.amazonaws.com/amazon-ssm-us-east-1/latest/linux_amd64/amazon-ssm-agent.rpm
    rpm -ivh /tmp/amazon-ssm-agent.rpm
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF

  tags = {
    Name = "${var.name_prefix}-monitor"
  }
}
