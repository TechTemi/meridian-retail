resource "aws_eip" "application" {
  domain   = "vpc"
  instance = aws_instance.application.id

  depends_on = [
    aws_internet_gateway.main
  ]

  tags = {
    Name    = "${local.name_prefix}-eip"
    Purpose = "StablePublicIngress"
  }
}
