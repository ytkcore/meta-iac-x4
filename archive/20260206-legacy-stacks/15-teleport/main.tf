provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  name_prefix = "${var.env}-${var.project}"
  domain_name = "teleport.${var.base_domain}"

  common_tags = merge(
    {
      Environment = var.env
      Project     = var.project
      ManagedBy   = "terraform"
      Stack       = "15-teleport"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Remote State
# -----------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/00-network.tfstate"
    region = var.state_region
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.env}/05-security.tfstate"
    region = var.state_region
  }
}

# -----------------------------------------------------------------------------
# ACM Certificate (for ALB)
# -----------------------------------------------------------------------------
data "aws_route53_zone" "main" {
  name = "${var.base_domain}."
}

resource "aws_acm_certificate" "teleport" {
  domain_name       = local.domain_name
  validation_method = "DNS"

  tags = {
    Name = "${local.name_prefix}-teleport-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "teleport_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.teleport.domain_validation_options : dvo.domain_name => dvo
  }

  allow_overwrite = true
  name            = each.value.resource_record_name
  records         = [each.value.resource_record_value]
  ttl             = 60
  type            = each.value.resource_record_type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "teleport" {
  certificate_arn         = aws_acm_certificate.teleport.arn
  validation_record_fqdns = [for record in aws_route53_record.teleport_cert_validation : record.fqdn]
}

# -----------------------------------------------------------------------------
# ALB (Application Load Balancer)
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-teleport-alb-sg"
  description = "Security Group for Teleport ALB"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from Internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress"
  }

  tags = {
    Name = "${local.name_prefix}-teleport-alb-sg"
  }
}

resource "aws_lb" "teleport" {
  name               = "${local.name_prefix}-teleport-alb"
  internal           = false # Public Access
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets = data.terraform_remote_state.network.outputs.subnet_ids_by_tier["public"]

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-teleport-alb"
  }
}

resource "aws_lb_target_group" "teleport" {
  name     = "${local.name_prefix}-teleport-tg"
  port     = 3080
  protocol = "HTTPS" # Web Traffic (HTTP/1.1)
  protocol_version = "HTTP1" # Explicitly revert to HTTP1 for non-gRPC traffic
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id

  health_check {
    path = "/web/login" # Teleport Health Check Endpoint (Login Page)
    # Teleport 3080 redirects to /web/login usually, check /health for API
    # Recommended: /readyz or /healthz on HTTPS
    port                = "traffic-port"
    protocol            = "HTTPS"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group" "teleport_grpc" {
  name     = "${local.name_prefix}-teleport-grpc"
  port     = 3080
  protocol = "HTTPS"
  protocol_version = "HTTP2" # For gRPC
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id

  health_check {
    path                = "/web/login"
    port                = "traffic-port"
    protocol            = "HTTPS"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

resource "aws_lb_listener_rule" "teleport_grpc" {
  listener_arn = aws_lb_listener.teleport_https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.teleport_grpc.arn
  }

  condition {
    http_header {
      http_header_name = "Content-Type"
      values           = ["application/grpc*"]
    }
  }
}

resource "aws_lb_listener" "teleport_https" {
  load_balancer_arn = aws_lb.teleport.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.teleport.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.teleport.arn
  }
}

# -----------------------------------------------------------------------------
# Route53 Record (Public DNS)
# -----------------------------------------------------------------------------
resource "aws_route53_record" "teleport" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.teleport.dns_name
    zone_id                = aws_lb.teleport.zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# Module: Teleport EC2
# -----------------------------------------------------------------------------
module "teleport" {
  source = "../../../modules/teleport-ec2"

  name       = "${local.name_prefix}-teleport"
  env        = var.env
  project    = var.project
  region     = var.region
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.subnet_ids_by_tier["common"]
  ami_id        = var.ami_id  # Optional override
  instance_type = var.instance_type
  cluster_name  = local.domain_name
  email         = var.email
  
  # Golden Image (handled by teleport-ec2 -> ec2-instance)
  state_bucket     = var.state_bucket
  state_region     = var.state_region
  state_key_prefix = var.state_key_prefix

  teleport_version = var.teleport_version
  enable_ha        = var.enable_ha

  alb_security_group_ids = [aws_security_group.alb.id]

  tags = local.common_tags
}

# ALB Target Attachment (for each instance)
resource "aws_lb_target_group_attachment" "teleport" {
  count = length(module.teleport.instance_ids)

  target_group_arn = aws_lb_target_group.teleport.arn
  target_id        = module.teleport.instance_ids[count.index]
  port             = 3080
}

resource "aws_lb_target_group_attachment" "teleport_grpc" {
  count = length(module.teleport.instance_ids)

  target_group_arn = aws_lb_target_group.teleport_grpc.arn
  target_id        = module.teleport.instance_ids[count.index]
  port             = 3080
}

