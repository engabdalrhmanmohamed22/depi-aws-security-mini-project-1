# Task 11 — Private RDS MySQL database
#
# Only the app servers can reach this database. No public IP, encrypted at
# rest, and the password is never written in code — it's generated randomly
# by Terraform and stored in Secrets Manager.

# ---------------------------------------------------------------------------
# DB subnet group — both private subnets, so RDS can place itself in either.
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "app" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.name_prefix}-db-subnet-group"
  }
}

# ---------------------------------------------------------------------------
# Random password — generated once by Terraform, never typed by a human,
# never committed to Git (it only exists in the state file and Secrets
# Manager, both of which are excluded from the repo per Task 1's .gitignore).
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 24
  special = false # avoids characters MySQL / connection strings sometimes choke on
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.name_prefix}-db-password"

  # Delete immediately on `terraform destroy` instead of the default 7-day
  # recovery window. This is a lab environment meant to be destroyed and
  # recreated often; the default window would otherwise block re-creating a
  # secret with the same name for up to 7 days (as happened once already).
  recovery_window_in_days = 0

  tags = {
    Name = "${var.name_prefix}-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.db.result
  })
}

# ---------------------------------------------------------------------------
# The database itself — private, encrypted, single-AZ (free tier).
# ---------------------------------------------------------------------------
resource "aws_db_instance" "app" {
  identifier     = "${var.name_prefix}-db"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az                = false

  username = "admin"
  password = random_password.db.result

  # Lab settings — this must be destroyable at the end of every session.
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "${var.name_prefix}-db"
  }
}
