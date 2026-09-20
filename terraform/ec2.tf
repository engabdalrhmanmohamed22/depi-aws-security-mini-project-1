# Task 8 — EC2 app servers: no key pair, no public IP, Session Manager only
#
# WHY THIS WORKS WITH NO INTERNET: the SSM Agent starts an OUTBOUND
# connection to the SSM service. The interface endpoints from Task 7 receive
# it privately inside the VPC. The instance never needs a public IP, and no
# inbound port is ever opened for management access.
#
# NOTE: the AMI resolved by the filter below does not ship with the SSM
# Agent pre-installed, so user_data installs it directly from the regional
# S3 bucket (standard, non-dualstack hostname — reachable via the S3
# Gateway Endpoint from Task 7). The demo web server uses Python's built-in
# http.server instead of nginx, since nginx would require dnf repo access
# that times out from a private subnet with no NAT (the AL2023 repo
# mirrorlist uses an S3 "dualstack" hostname the Gateway Endpoint does not
# cover).

# ---------------------------------------------------------------------------
# Always use the latest Amazon Linux 2023 AMI — never hard-code an AMI ID.
# ---------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Server in private-a (us-east-1a)
# ---------------------------------------------------------------------------
resource "aws_instance" "app_a" {
  ami                          = data.aws_ami.amazon_linux_2023.id
  instance_type                = "t3.micro"
  subnet_id                    = aws_subnet.private_a.id
  vpc_security_group_ids       = [aws_security_group.app.id]
  iam_instance_profile         = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address  = false
  user_data_replace_on_change  = true
  # No key_name set at all — Session Manager only, no SSH.

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    # This AMI variant does NOT ship with the SSM Agent pre-installed.
    # Install it directly from the regional S3 bucket using the standard
    # (non-dualstack) hostname, which IS covered by the S3 Gateway Endpoint —
    # this avoids dnf/repo metadata entirely.
    curl -s -o /tmp/amazon-ssm-agent.rpm https://s3.us-east-1.amazonaws.com/amazon-ssm-us-east-1/latest/linux_amd64/amazon-ssm-agent.rpm
    rpm -ivh /tmp/amazon-ssm-agent.rpm
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # This AMI's dnf mirrorlist hands back a URL using the S3 "dualstack"
    # hostname, which has no route from this private subnet (the S3 Gateway
    # Endpoint only covers the standard hostname). Fetch the mirrorlist over
    # the working (non-dualstack) hostname, rewrite the dualstack URL it
    # returns, and pin dnf to that as a static repo — this lets dnf install
    # ANY package (not just one file), fixing the root cause properly.
    RELEASEVER=$(grep -oP '(?<=PRETTY_NAME="Amazon Linux )[0-9.]+' /etc/os-release)
    MIRROR_HOST="al2023-repos-us-east-1-de612dc2.s3.us-east-1.amazonaws.com"
    BASEURL=$(curl -s "https://$MIRROR_HOST/core/mirrors/$RELEASEVER/x86_64/mirror.list" | sed 's#s3\.dualstack\.us-east-1#s3.us-east-1#' | head -1)

    cat > /etc/yum.repos.d/amazonlinux-fixed.repo <<REPOEOF
    [amazonlinux-fixed]
    name=Amazon Linux 2023 core (non-dualstack fix)
    baseurl=$BASEURL
    enabled=1
    gpgcheck=0
    priority=1
    REPOEOF

    dnf install -y --disablerepo="*" --enablerepo="amazonlinux-fixed" nfs-utils

    mkdir -p /mnt/shared
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${aws_efs_file_system.app.dns_name}:/ /mnt/shared
    echo "${aws_efs_file_system.app.dns_name}:/ /mnt/shared nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab

    mkdir -p /var/www
    echo "<h1>Hello from us-east-1a (depi-sec-app-a)</h1>" > /var/www/index.html

    cat <<'UNIT' > /etc/systemd/system/webserver.service
    [Unit]
    Description=Simple Python web server
    After=network.target

    [Service]
    WorkingDirectory=/var/www
    ExecStart=/usr/bin/python3 -m http.server 80
    Restart=always

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable webserver
    systemctl start webserver
  EOF

  tags = {
    Name = "${var.name_prefix}-app-a"
  }
}

# ---------------------------------------------------------------------------
# Server in private-b (us-east-1b)
# ---------------------------------------------------------------------------
resource "aws_instance" "app_b" {
  ami                          = data.aws_ami.amazon_linux_2023.id
  instance_type                = "t3.micro"
  subnet_id                    = aws_subnet.private_b.id
  vpc_security_group_ids       = [aws_security_group.app.id]
  iam_instance_profile         = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address  = false
  user_data_replace_on_change  = true
  # No key_name set at all — Session Manager only, no SSH.

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    # This AMI variant does NOT ship with the SSM Agent pre-installed.
    # Install it directly from the regional S3 bucket using the standard
    # (non-dualstack) hostname, which IS covered by the S3 Gateway Endpoint —
    # this avoids dnf/repo metadata entirely.
    curl -s -o /tmp/amazon-ssm-agent.rpm https://s3.us-east-1.amazonaws.com/amazon-ssm-us-east-1/latest/linux_amd64/amazon-ssm-agent.rpm
    rpm -ivh /tmp/amazon-ssm-agent.rpm
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # This AMI's dnf mirrorlist hands back a URL using the S3 "dualstack"
    # hostname, which has no route from this private subnet (the S3 Gateway
    # Endpoint only covers the standard hostname). Fetch the mirrorlist over
    # the working (non-dualstack) hostname, rewrite the dualstack URL it
    # returns, and pin dnf to that as a static repo — this lets dnf install
    # ANY package (not just one file), fixing the root cause properly.
    RELEASEVER=$(grep -oP '(?<=PRETTY_NAME="Amazon Linux )[0-9.]+' /etc/os-release)
    MIRROR_HOST="al2023-repos-us-east-1-de612dc2.s3.us-east-1.amazonaws.com"
    BASEURL=$(curl -s "https://$MIRROR_HOST/core/mirrors/$RELEASEVER/x86_64/mirror.list" | sed 's#s3\.dualstack\.us-east-1#s3.us-east-1#' | head -1)

    cat > /etc/yum.repos.d/amazonlinux-fixed.repo <<REPOEOF
    [amazonlinux-fixed]
    name=Amazon Linux 2023 core (non-dualstack fix)
    baseurl=$BASEURL
    enabled=1
    gpgcheck=0
    priority=1
    REPOEOF

    dnf install -y --disablerepo="*" --enablerepo="amazonlinux-fixed" nfs-utils

    mkdir -p /mnt/shared
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${aws_efs_file_system.app.dns_name}:/ /mnt/shared
    echo "${aws_efs_file_system.app.dns_name}:/ /mnt/shared nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab

    mkdir -p /var/www
    echo "<h1>Hello from us-east-1b (depi-sec-app-b)</h1>" > /var/www/index.html

    cat <<'UNIT' > /etc/systemd/system/webserver.service
    [Unit]
    Description=Simple Python web server
    After=network.target

    [Service]
    WorkingDirectory=/var/www
    ExecStart=/usr/bin/python3 -m http.server 80
    Restart=always

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable webserver
    systemctl start webserver
  EOF

  tags = {
    Name = "${var.name_prefix}-app-b"
  }
}
