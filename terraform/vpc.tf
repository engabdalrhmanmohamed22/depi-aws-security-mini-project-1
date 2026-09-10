# ---------------------------------------------------------------------------
# Task 4 — VPC, subnets, and routing
#
# THE RULE TO REMEMBER: a subnet is not public because of its name.
# A subnet is public because its route table has a route to an
# Internet Gateway. That is the only real difference.
# ---------------------------------------------------------------------------

resource "aws_vpc" "app" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-app-vpc"
  }
}

# ---------------------------------------------------------------------------
# Subnets — two AZs, one public + one private subnet in each
# ---------------------------------------------------------------------------

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-b"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.0.12.0/24"
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-b"
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway — only the public route table points here
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ---------------------------------------------------------------------------
# Public route table — the ONLY route table with a path to the internet
# ---------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private route table — deliberately has NO internet route.
# Only the default "local" route exists here (added automatically by AWS),
# plus a route to the peered tools VPC and a VPC endpoint route added in
# later tasks.
# ---------------------------------------------------------------------------

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
