resource "aws_security_group" "application" {
  name        = "${local.name_prefix}-app-sg"
  description = "Network access controls for the Meridian application host."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-app-sg"
  }
}


resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.application.id

  description = "Public HTTP access for redirect and ACME validation."
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}


resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.application.id

  description = "Public HTTPS access to Meridian."
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}


resource "aws_vpc_security_group_ingress_rule" "ssh_admin" {
  security_group_id = aws_security_group.application.id

  description = "Administrative SSH from the explicitly authorized public IPv4 address."
  cidr_ipv4   = var.admin_cidr
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
}


resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.application.id

  description = "Outbound IPv4 access for package installation, ECR, S3, DNS updates, and certificate operations."
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
