# ------------------------------------------------------------------------------
# Route53 Private Hosted Zone
# ------------------------------------------------------------------------------

resource "aws_route53_zone" "private" {
  count = var.base_domain != "" ? 1 : 0

  name = var.base_domain
  vpc {
    vpc_id = aws_vpc.this.id
  }

  tags = merge(var.tags, {
    Name        = "${var.project}-${var.env}-private-zone"
    Environment = var.env
    Project     = var.project
  })
}
