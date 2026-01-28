# -----------------------------------------------------------------------------
# Harbor EC2 Module - user_data(bootstrapping) 방식
# - EC2 부팅 시점(cloud-init)에서 Harbor를 설치합니다.
# - 설치/재시도는 systemd 서비스로 수행되며, 설치 로그는 인스턴스에 남습니다.
#   - /var/log/harbor-bootstrap.log
#   - /var/log/harbor-install.log
# -----------------------------------------------------------------------------

locals {
  use_s3 = var.storage_type == "s3"
}

# -----------------------------------------------------------------------------
# 1. S3 Bucket (optional: only when storage_type == "s3")
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "created" {
  count         = local.use_s3 && var.create_bucket ? 1 : 0
  bucket        = var.target_bucket_name
  force_destroy = false
}

data "aws_s3_bucket" "existing" {
  count  = local.use_s3 && !var.create_bucket ? 1 : 0
  bucket = var.target_bucket_name
}

locals {
  final_bucket_id  = local.use_s3 ? (var.create_bucket ? aws_s3_bucket.created[0].id : data.aws_s3_bucket.existing[0].id) : null
  final_bucket_arn = local.use_s3 ? (var.create_bucket ? aws_s3_bucket.created[0].arn : data.aws_s3_bucket.existing[0].arn) : null
}

# -----------------------------------------------------------------------------
# 2. Security Group (Harbor)
#  - 기본: 80(HTTP)만 오픈
#  - enable_tls=true 인 경우에만 443 오픈
#  - SSH는 allow_ssh_cidrs를 지정한 경우에만 오픈 (SSM 접속 권장)
# -----------------------------------------------------------------------------
resource "aws_security_group" "harbor" {
  name        = "${var.name}-${var.env}-sg"
  description = "Security Group for Harbor Registry"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.enable_tls ? [1] : []
    content {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "ingress" {
    for_each = length(var.allow_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "SSH (optional)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allow_ssh_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-${var.env}-sg"
    Environment = var.env
  }
}

# -----------------------------------------------------------------------------
# 3. Data Sources
# -----------------------------------------------------------------------------
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# 4. EC2 Instance (user_data로 Harbor 설치)
# -----------------------------------------------------------------------------
module "ec2" {
  source = "../ec2-instance"

  name                   = var.name
  env                    = var.env
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.harbor.id]
  key_name               = var.key_name
  root_volume_size       = var.root_volume_size

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    harbor_version = var.harbor_version
    hostname       = var.harbor_hostname
    enable_tls     = tostring(var.enable_tls)
    admin_password = var.admin_password
    db_password    = var.db_password
    alb_dns_name  = try(aws_lb.harbor[0].dns_name, "")

    //s3_region    = data.aws_region.current.name
    storage_type = var.storage_type
    s3_region    = data.aws_region.current.id
    s3_bucket    = local.use_s3 ? local.final_bucket_id : ""
    data_volume  = "/data/harbor"

    # Proxy cache
    create_proxy_cache  = tostring(var.create_proxy_cache)
    proxy_cache_project = var.proxy_cache_project

    # Helm chart seeding (OCI)
    seed_helm_charts          = tostring(var.seed_helm_charts)
    argocd_chart_version      = var.argocd_chart_version
    certmanager_chart_version = var.certmanager_chart_version
    rancher_chart_version     = var.rancher_chart_version
  })
}

# -----------------------------------------------------------------------------
# 5. IAM Policies
#  - S3는 storage_type == "s3"인 경우에만 권한 부여
# -----------------------------------------------------------------------------
locals {
  ecr_statement = {
    Effect = "Allow"
    Action = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    Resource = "*"
  }

  s3_statements = local.use_s3 ? [
    {
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
      Resource = [local.final_bucket_arn]
    },
    {
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ]
      Resource = ["${local.final_bucket_arn}/*"]
    }
  ] : []
}

resource "aws_iam_role_policy" "harbor_permissions" {
  name = "harbor-s3-ecr-policy"
  role = module.ec2.iam_role_name

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.s3_statements, [local.ecr_statement])
  })
}

# -----------------------------------------------------------------------------
# 6. ALB for Harbor (Optional)
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  count = var.enable_alb ? 1 : 0

  name        = "${var.name}-${var.env}-alb-sg"
  description = "Security Group for Harbor ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.alb_ingress_cidrs
  }

  dynamic "ingress" {
    for_each = var.alb_certificate_arn != null ? [1] : []
    content {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.alb_ingress_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-${var.env}-alb-sg"
    Environment = var.env
  }
}

# Allow ALB to reach Harbor EC2
resource "aws_security_group_rule" "harbor_from_alb" {
  count = var.enable_alb ? 1 : 0

  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.harbor.id
  source_security_group_id = aws_security_group.alb[0].id
  description              = "Allow HTTP from ALB"
}

resource "aws_lb" "harbor" {
  count = var.enable_alb ? 1 : 0

  name               = "${var.name}-${var.env}-alb"
  internal           = var.alb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = var.alb_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "${var.name}-${var.env}-alb"
    Environment = var.env
  }
}

resource "aws_lb_target_group" "harbor" {
  count = var.enable_alb ? 1 : 0

  name     = "${var.name}-${var.env}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/api/v2.0/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name        = "${var.name}-${var.env}-tg"
    Environment = var.env
  }
}

resource "aws_lb_target_group_attachment" "harbor" {
  count = var.enable_alb ? 1 : 0

  target_group_arn = aws_lb_target_group.harbor[0].arn
  target_id        = module.ec2.instance_id
  port             = 80
}

# HTTP Listener (redirect to HTTPS if certificate exists, otherwise forward)
resource "aws_lb_listener" "http" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.harbor[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.alb_certificate_arn != null ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.alb_certificate_arn != null ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.alb_certificate_arn == null ? [1] : []
      content {
        target_group {
          arn = aws_lb_target_group.harbor[0].arn
        }
      }
    }
  }
}

# HTTPS Listener (only if certificate is provided)
resource "aws_lb_listener" "https" {
  count = var.enable_alb && var.alb_certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.harbor[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.harbor[0].arn
  }
}
