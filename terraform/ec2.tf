data "aws_ssm_parameter" "ubuntu_2204_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}


resource "aws_key_pair" "application" {
  key_name   = "${local.name_prefix}-admin"
  public_key = trimspace(var.ec2_ssh_public_key)

  tags = {
    Name    = "${local.name_prefix}-admin"
    Purpose = "AdministratorSSH"
  }
}


resource "aws_instance" "application" {
  ami           = nonsensitive(data.aws_ssm_parameter.ubuntu_2204_ami.value)
  instance_type = var.instance_type

  subnet_id = aws_subnet.public.id

  vpc_security_group_ids = [
    aws_security_group.application.id
  ]

  iam_instance_profile = aws_iam_instance_profile.application.name
  key_name             = aws_key_pair.application.key_name


  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
  }

  tags = {
    Name = "${local.name_prefix}-app"
    Role = "ApplicationHost"
  }
}
