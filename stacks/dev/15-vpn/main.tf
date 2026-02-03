#------------------------------------------------------------------------------
# AWS Client VPN Stack
# 
# 개발팀 VPN 접근을 위한 AWS Client VPN Endpoint 구성
# - Mutual Authentication (인증서 기반)
# - Split Tunnel 활성화 (VPC 트래픽만 VPN 경유)
# - CloudWatch 연결 로그
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

#------------------------------------------------------------------------------
# Local Variables
#------------------------------------------------------------------------------
locals {
  name_prefix = "${var.env}-${var.project}"

  common_tags = merge(
    {
      Environment = var.env
      Project     = var.project
      ManagedBy   = "terraform"
      Stack       = "15-vpn"
    },
    var.tags
  )
}

#------------------------------------------------------------------------------
# Remote State - VPC 정보
#------------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/00-network/terraform.tfstate"
    region = var.state_region
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/10-security/terraform.tfstate"
    region = var.state_region
  }
}

#------------------------------------------------------------------------------
# CloudWatch Log Group - VPN 연결 로그
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/${local.name_prefix}-client-vpn"
  retention_in_days = var.vpn_log_retention_days

  tags = {
    Name = "${local.name_prefix}-vpn-logs"
  }
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "connection-log"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

#------------------------------------------------------------------------------
# TLS 인증서 생성 (Self-Signed)
# 
# 프로덕션에서는 AWS Private CA 또는 외부 CA 사용 권장
#------------------------------------------------------------------------------

# CA Private Key
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# CA Certificate (Self-Signed)
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${local.name_prefix}-vpn-ca"
    organization = var.project
  }

  validity_period_hours = var.vpn_cert_validity_days * 24
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Server Private Key
resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Server Certificate Request
resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = "${local.name_prefix}-vpn-server"
    organization = var.project
  }
}

# Server Certificate (CA에서 서명)
resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.vpn_cert_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Client Private Key
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Client Certificate Request
resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "${local.name_prefix}-vpn-client"
    organization = var.project
  }
}

# Client Certificate (CA에서 서명)
resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.vpn_cert_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

#------------------------------------------------------------------------------
# ACM에 인증서 업로드
#------------------------------------------------------------------------------
resource "aws_acm_certificate" "server" {
  count = var.vpn_server_cert_arn == null ? 1 : 0

  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = {
    Name = "${local.name_prefix}-vpn-server-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "client" {
  count = var.vpn_client_cert_arn == null ? 1 : 0

  private_key       = tls_private_key.client.private_key_pem
  certificate_body  = tls_locally_signed_cert.client.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = {
    Name = "${local.name_prefix}-vpn-client-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  server_cert_arn = var.vpn_server_cert_arn != null ? var.vpn_server_cert_arn : aws_acm_certificate.server[0].arn
  client_cert_arn = var.vpn_client_cert_arn != null ? var.vpn_client_cert_arn : aws_acm_certificate.client[0].arn
}

#------------------------------------------------------------------------------
# VPN Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "vpn" {
  name        = "${local.name_prefix}-vpn-endpoint"
  description = "Security Group for Client VPN Endpoint"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # VPN 클라이언트로부터의 모든 트래픽 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpn_cidr_block]
    description = "Allow all from VPN clients"
  }

  # VPC 내부로의 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.terraform_remote_state.network.outputs.vpc_cidr]
    description = "Allow all to VPC"
  }

  tags = {
    Name = "${local.name_prefix}-vpn-endpoint-sg"
  }
}

#------------------------------------------------------------------------------
# Client VPN Endpoint
#------------------------------------------------------------------------------
resource "aws_ec2_client_vpn_endpoint" "main" {
  description            = "${local.name_prefix} Client VPN"
  server_certificate_arn = local.server_cert_arn
  client_cidr_block      = var.vpn_cidr_block

  # Mutual Authentication (인증서 기반)
  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = local.client_cert_arn
  }

  # 연결 로그
  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  # Split Tunnel 설정
  split_tunnel = var.vpn_split_tunnel

  # VPC 연결
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  security_group_ids = [aws_security_group.vpn.id]

  # DNS 설정 (비어있으면 VPC DNS 자동 사용)
  dns_servers = length(var.vpn_dns_servers) > 0 ? var.vpn_dns_servers : null

  # 세션 타임아웃
  session_timeout_hours = var.vpn_session_timeout_hours

  # TLS 설정
  transport_protocol = "udp"
  vpn_port           = 443

  tags = {
    Name = "${local.name_prefix}-client-vpn"
  }
}

#------------------------------------------------------------------------------
# VPN Network Association (서브넷 연결)
#------------------------------------------------------------------------------
resource "aws_ec2_client_vpn_network_association" "main" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  subnet_id              = data.terraform_remote_state.network.outputs.subnet_ids[var.vpn_subnet_key]
}

#------------------------------------------------------------------------------
# VPN Authorization Rule (VPC 전체 접근 허용)
#------------------------------------------------------------------------------
resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = data.terraform_remote_state.network.outputs.vpc_cidr
  authorize_all_groups   = true
  description            = "Allow access to entire VPC"
}

#------------------------------------------------------------------------------
# VPN Route (VPC로 라우팅)
#------------------------------------------------------------------------------
resource "aws_ec2_client_vpn_route" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  destination_cidr_block = data.terraform_remote_state.network.outputs.vpc_cidr
  target_vpc_subnet_id   = aws_ec2_client_vpn_network_association.main.subnet_id
  description            = "Route to VPC"
}

#------------------------------------------------------------------------------
# 클라이언트 설정 파일 로컬 저장 (편의용)
#------------------------------------------------------------------------------
resource "local_file" "client_key" {
  content         = tls_private_key.client.private_key_pem
  filename        = "${path.module}/generated/client.key"
  file_permission = "0600"
}

resource "local_file" "client_cert" {
  content         = tls_locally_signed_cert.client.cert_pem
  filename        = "${path.module}/generated/client.crt"
  file_permission = "0644"
}

resource "local_file" "ca_cert" {
  content         = tls_self_signed_cert.ca.cert_pem
  filename        = "${path.module}/generated/ca.crt"
  file_permission = "0644"
}
