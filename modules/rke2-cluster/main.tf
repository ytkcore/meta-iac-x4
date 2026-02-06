##############################
# RKE2 Cluster on EC2 (Self-managed)
#
# - Pure Terraform Implementation
# - No external cleanup scripts embedded (Manual cleanup required on failure)
##############################

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ssm_parameter" "ubuntu_2204_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

data "aws_vpc" "this" {
  id = var.vpc_id
}
resource "random_password" "rke2_token" {
  length  = 32
  special = false
}

locals {
  # Name Format: {env}-{project}-{workload}-{resource}-{suffix}
  name_prefix = "${var.env}-${var.project}-${var.name}"

  # Token & AMI
  token = coalesce(var.rke2_token, random_password.rke2_token.result)
  ami_id = var.ami_id != null ? var.ami_id : (
    var.os_family == "ubuntu2204" ? data.aws_ssm_parameter.ubuntu_2204_ami.value : data.aws_ssm_parameter.al2023_ami.value
  )

  # Subnets
  cp_subnets = distinct(length(var.control_plane_subnet_ids) > 0 ? var.control_plane_subnet_ids : var.private_subnet_ids)
  dp_subnets = distinct(length(var.worker_subnet_ids) > 0 ? var.worker_subnet_ids : var.private_subnet_ids)

  # Cluster endpoints
  server_url = "https://${aws_lb.rke2[0].dns_name}:9345"
  tls_san    = aws_lb.rke2[0].dns_name

  # Node maps
  control_planes = {
    for i in range(var.control_plane_count) :
    format("cp-%02d", i + 1) => {
      subnet_id = local.cp_subnets[i % length(local.cp_subnets)]
      bootstrap = i == 0
    }
  }

  workers = {
    for i in range(var.worker_count) :
    format("worker-%02d", i + 1) => {
      subnet_id = local.dp_subnets[i % length(local.dp_subnets)]
    }
  }

  # Ingress backend (ACM TLS termination support)
  ingress_backend_port     = var.enable_acm_tls_termination ? var.ingress_http_nodeport : var.ingress_https_nodeport
  ingress_backend_protocol = var.enable_acm_tls_termination ? "TCP" : "TCP"

  # Tags
  cluster_name = "${var.project}-${var.env}-k8s"
  common_tags = merge(
    var.tags,
    {
      Project                                       = var.project
      Env                                           = var.env
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    }
  )
}

##############################
# IAM & Security Groups
##############################
resource "aws_iam_role" "nodes" {
  name = "${local.name_prefix}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each   = toset(var.extra_policy_arns)
  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}

# AWS Cloud Provider (RKE2) permissions for ELB management
resource "aws_iam_policy" "nodes_elb" {
  name        = "${local.name_prefix}-elb-policy"
  description = "Permissions for RKE2 nodes to manage AWS Load Balancers"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeInstances",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeTags",
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          # CCM Required Permissions
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeVolumes",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyVolume",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeInstanceTopology"
        ]
        Resource = "*"
      }
    ]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "nodes_elb" {
  role       = aws_iam_role.nodes.name
  policy_arn = aws_iam_policy.nodes_elb.arn
}

resource "aws_iam_instance_profile" "nodes" {
  name = "${local.name_prefix}-profile"
  role = aws_iam_role.nodes.name
  tags = local.common_tags
}

resource "aws_security_group" "nodes" {
  name        = "${local.name_prefix}-common-sg"
  description = "RKE2 nodes SG"
  vpc_id      = var.vpc_id

  ingress {
    description = "Self"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "K8s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "RKE2 Supervisor"
    from_port   = 9345
    to_port     = 9345
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Outbound All"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-common-sg" })
}

##############################
# Internal NLB
##############################
resource "aws_lb" "rke2" {
  count              = 1
  name               = substr("${local.name_prefix}-nlb-server", 0, 32)
  internal           = true
  load_balancer_type = "network"
  subnets            = local.cp_subnets

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nlb-server" })
}

resource "aws_lb_target_group" "supervisor" {
  count       = 1
  name        = substr("${local.name_prefix}-tg-9345", 0, 32)
  port        = 9345
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    protocol = "TCP"
    port     = "9345"
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "apiserver" {
  count       = 1
  name        = substr("${local.name_prefix}-tg-6443", 0, 32)
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    protocol = "TCP"
    port     = "6443"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "supervisor" {
  count             = 1
  load_balancer_arn = aws_lb.rke2[0].arn
  port              = 9345
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.supervisor[0].arn
  }
}

resource "aws_lb_listener" "apiserver" {
  count             = 1
  load_balancer_arn = aws_lb.rke2[0].arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apiserver[0].arn
  }
}

##############################
# EC2 Instances (using ec2-instance module)
##############################

# Control Plane Nodes
module "control_plane" {
  source   = "../ec2-instance"
  for_each = local.control_planes

  name    = "${var.name}-${each.key}"
  env     = var.env
  project = var.project
  region  = var.region

  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  instance_type          = var.instance_type
  root_volume_size       = var.root_volume_size_gb

  # Use shared IAM instance profile (external)
  iam_instance_profile = aws_iam_instance_profile.nodes.name

  # Kubernetes cluster tags for AWS CCM
  tags = local.common_tags

  # Golden Image Configuration
  state_bucket       = var.state_bucket
  state_region       = var.state_region
  state_key_prefix   = var.state_key_prefix
  ami_id             = var.ami_id
  allow_ami_fallback = var.allow_ami_fallback

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/rke2-server-userdata.sh.tftpl", {
    rke2_version = var.rke2_version
    token        = local.token
    tls_san      = local.tls_san
    server_url   = local.server_url
    is_bootstrap = each.value.bootstrap
    node_name    = each.key
    os_family    = var.os_family
    harbor_registry_hostport          = var.harbor_registry_hostport != null ? var.harbor_registry_hostport : ""
    harbor_hostname                   = var.harbor_hostname != null ? var.harbor_hostname : ""
    harbor_private_ip                 = var.harbor_private_ip != null ? var.harbor_private_ip : ""
    harbor_add_hosts_entry            = var.harbor_add_hosts_entry
    harbor_scheme                     = var.harbor_scheme
    harbor_proxy_project              = var.harbor_proxy_project
    enable_image_prepull              = var.enable_image_prepull
    image_prepull_source              = var.image_prepull_source
    disable_default_registry_fallback = var.disable_default_registry_fallback
    harbor_tls_insecure_skip_verify   = var.harbor_tls_insecure_skip_verify
    harbor_auth_enabled               = var.harbor_auth_enabled
    harbor_username                   = var.harbor_username
    harbor_password                   = var.harbor_password
    configure_ingress_nodeport        = var.configure_ingress_nodeport
    ingress_http_nodeport             = var.ingress_http_nodeport
    ingress_https_nodeport            = var.ingress_https_nodeport
    ingress_external_traffic_policy   = var.ingress_external_traffic_policy
    health_check_script               = file("${path.module}/../../scripts/rke2/check-rke2-health.sh")
    enable_aws_ccm                    = var.enable_aws_ccm
    aws_ccm_version                   = var.aws_ccm_version
    cluster_name                      = local.cluster_name
  }))

  depends_on = [aws_lb.rke2]
}

# Worker Nodes
module "worker" {
  source   = "../ec2-instance"
  for_each = local.workers

  name    = "${var.name}-${each.key}"
  env     = var.env
  project = var.project
  region  = var.region

  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  instance_type          = var.instance_type
  root_volume_size       = var.root_volume_size_gb

  # Use shared IAM instance profile (external)
  iam_instance_profile = aws_iam_instance_profile.nodes.name

  # Kubernetes cluster tags for AWS CCM
  tags = local.common_tags

  # Golden Image Configuration
  state_bucket       = var.state_bucket
  state_region       = var.state_region
  state_key_prefix   = var.state_key_prefix
  ami_id             = var.ami_id
  allow_ami_fallback = var.allow_ami_fallback

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/rke2-agent-userdata.sh.tftpl", {
    rke2_version                      = var.rke2_version
    token                             = local.token
    server_url                        = local.server_url
    node_name                         = each.key
    os_family                         = var.os_family
    harbor_registry_hostport          = var.harbor_registry_hostport != null ? var.harbor_registry_hostport : ""
    harbor_hostname                   = var.harbor_hostname != null ? var.harbor_hostname : ""
    harbor_private_ip                 = var.harbor_private_ip != null ? var.harbor_private_ip : ""
    harbor_add_hosts_entry            = var.harbor_add_hosts_entry
    harbor_scheme                     = var.harbor_scheme
    harbor_proxy_project              = var.harbor_proxy_project
    enable_image_prepull              = var.enable_image_prepull
    image_prepull_source              = var.image_prepull_source
    disable_default_registry_fallback = var.disable_default_registry_fallback
    harbor_tls_insecure_skip_verify   = var.harbor_tls_insecure_skip_verify
    harbor_auth_enabled               = var.harbor_auth_enabled
    harbor_username                   = var.harbor_username
    harbor_password                   = var.harbor_password
  }))

  depends_on = [module.control_plane]
}
##############################
# Target Attachments (CP)
##############################
resource "aws_lb_target_group_attachment" "supervisor" {
  for_each         = local.control_planes
  target_group_arn = aws_lb_target_group.supervisor[0].arn
  target_id        = module.control_plane[each.key].id
  port             = 9345
}

resource "aws_lb_target_group_attachment" "apiserver" {
  for_each         = local.control_planes
  target_group_arn = aws_lb_target_group.apiserver[0].arn
  target_id        = module.control_plane[each.key].id
  port             = 6443
}

##############################
# Ingress NLB (Optional)
#
# 두 가지 모드 지원:
# 1. TCP Passthrough (기본): 443 TCP → NodePort 30443
# 2. ACM TLS Termination: 443 TLS(ACM) → NodePort 30080 (HTTP)
##############################

resource "aws_lb" "ingress" {
  count              = var.enable_public_ingress_nlb ? 1 : 0
  name               = substr("${local.name_prefix}-nlb-ingress", 0, 32)
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  # ACM TLS 사용 시 cross-zone load balancing 권장
  enable_cross_zone_load_balancing = var.enable_acm_tls_termination ? true : false

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nlb-ingress" })
}

resource "aws_lb_target_group" "ingress_http" {
  count              = var.enable_public_ingress_nlb ? 1 : 0
  name               = substr("${local.name_prefix}-tg-http", 0, 32)
  port               = var.ingress_http_nodeport
  protocol           = "TCP"
  preserve_client_ip = false
  target_type        = "instance"
  vpc_id             = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.common_tags
}

# HTTPS 백엔드 타겟 그룹 (TCP Passthrough 모드에서만 사용)
resource "aws_lb_target_group" "ingress_https" {
  count              = var.enable_public_ingress_nlb && !var.enable_acm_tls_termination ? 1 : 0
  name               = substr("${local.name_prefix}-tg-https", 0, 32)
  port               = var.ingress_https_nodeport
  protocol           = "TCP"
  preserve_client_ip = false
  target_type        = "instance"
  vpc_id             = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.common_tags
}

# HTTP Listener (포트 80)
resource "aws_lb_listener" "ingress_http" {
  count             = var.enable_public_ingress_nlb && var.enable_public_ingress_http_listener ? 1 : 0
  load_balancer_arn = aws_lb.ingress[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_http[0].arn
  }
}

# HTTPS Listener - TCP Passthrough 모드 (ACM 미사용)
resource "aws_lb_listener" "ingress_https_passthrough" {
  count             = var.enable_public_ingress_nlb && !(var.enable_acm_tls_termination && var.acm_certificate_arn != null) ? 1 : 0
  load_balancer_arn = aws_lb.ingress[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_https[0].arn
  }
}

# HTTPS Listener - ACM TLS Termination 모드
resource "aws_lb_listener" "ingress_https_tls" {
  count             = var.enable_public_ingress_nlb && var.enable_acm_tls_termination && var.acm_certificate_arn != null ? 1 : 0
  load_balancer_arn = aws_lb.ingress[0].arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = var.acm_ssl_policy
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_http[0].arn # HTTP 백엔드로 전달
  }
}

# Target Group Attachments - HTTP
resource "aws_lb_target_group_attachment" "ingress_http" {
  for_each         = var.enable_public_ingress_nlb ? local.workers : {}
  target_group_arn = aws_lb_target_group.ingress_http[0].arn
  target_id        = module.worker[each.key].id
  port             = var.ingress_http_nodeport
}

# Target Group Attachments - HTTPS (TCP Passthrough 모드에서만)
resource "aws_lb_target_group_attachment" "ingress_https" {
  for_each         = var.enable_public_ingress_nlb && !var.enable_acm_tls_termination ? local.workers : {}
  target_group_arn = aws_lb_target_group.ingress_https[0].arn
  target_id        = module.worker[each.key].id
  port             = var.ingress_https_nodeport
}

resource "aws_security_group_rule" "ingress_http_from_public" {
  count             = var.enable_public_ingress_nlb ? 1 : 0
  type              = "ingress"
  from_port         = var.ingress_http_nodeport
  to_port           = var.ingress_http_nodeport
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.this.cidr_block]
  security_group_id = aws_security_group.nodes.id
  description       = "Ingress HTTP NodePort (from VPC CIDR only)"
}

resource "aws_security_group_rule" "ingress_https_from_public" {
  count             = var.enable_public_ingress_nlb && !(var.enable_acm_tls_termination && var.acm_certificate_arn != null) ? 1 : 0
  type              = "ingress"
  from_port         = var.ingress_https_nodeport
  to_port           = var.ingress_https_nodeport
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nodes.id
  description       = "Ingress HTTPS NodePort (TCP Passthrough)"
}
