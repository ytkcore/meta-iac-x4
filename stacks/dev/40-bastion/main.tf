locals {
  # backend 관련 변수들을 "사용"한 것으로 처리하여 경고/린트 노이즈를 줄입니다.
  # (terraform init backend-config 값은 Makefile에서 주입하지만, env.tfvars에 함께 들어오는 경우가 있어 선언/참조를 유지합니다.)
  _backend_settings = {
    bucket     = var.state_bucket
    region     = var.state_region
    key_prefix = var.state_key_prefix
    azs        = var.azs
  }
}

# 00-network 스택의 출력값(VPC/서브넷 등)을 참조합니다.
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "${var.state_key_prefix}/${var.env}/00-network.tfstate"
    region  = var.state_region
    encrypt = true
  }
}

locals {
  tags = merge(var.tags, {
    Environment = var.env
    Project     = var.project
  })

  # bastion을 배치할 서브넷 키(예: "common-private-a")에 해당하는 subnet id
  bastion_subnet_id = data.terraform_remote_state.network.outputs.subnet_ids[var.bastion_subnet_key]

  # Bastion 부트스트랩 유틸(helm/kubectl 및 helper script) 설치
  bastion_user_data = var.enable_bootstrap_tools ? templatefile("${path.module}/user_data/bastion-bootstrap.sh.tftpl", {
    project         = var.project
    env             = var.env
    name            = var.name
    region          = var.region
    argocd_nodeport = var.argocd_nodeport
  }) : null
}

# ---------------------------------------------------------------------------
# Bastion 보안그룹 (SSM only 기본)
# - 기본적으로 인바운드(SSH 등)를 허용하지 않습니다.
# - 아웃바운드는 운영 편의상 전체 허용(필요 시 제한 가능)
# - Break-glass 상황에서는 운영자가 임시 SG를 콘솔/CLI로 수동 부착하여 SSH 접근을 허용합니다.
# ---------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  count       = var.bastion_security_group_id == null ? 1 : 0
  name_prefix = "${var.name}-bastion-"
  description = "Bastion SG (SSM only, no ingress by default)"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # ingress 없음: SSM only

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

locals {
  # 외부에서 SG를 주입하지 않으면, 위에서 생성한 SG를 사용합니다.
  bastion_sg_id  = var.bastion_security_group_id != null ? var.bastion_security_group_id : try(aws_security_group.bastion[0].id, null)
  bastion_sg_ids = compact([local.bastion_sg_id])
}

module "bastion" {
  source = "../../../modules/ec2-instance"

  name   = "${var.name}-bastion-a"
  env    = var.env
  region = var.region

  subnet_id              = local.bastion_subnet_id
  vpc_security_group_ids = local.bastion_sg_ids
  instance_type          = var.instance_type

  # SSM-only (SSH key 미사용)
  key_name = null

  # Tools bootstrap (kubectl/helm + helper scripts)
  user_data        = local.bastion_user_data
  root_volume_size = var.root_volume_size
}

# Bastion에서 SSM SendCommand로 Control Plane kubeconfig를 가져오는 등
# '부트스트랩 작업을 자동화'하기 위해 필요한 최소 권한을 Bastion 인스턴스 Role에 부여합니다.
resource "aws_iam_policy" "bastion_bootstrap" {
  count       = var.enable_bootstrap_tools ? 1 : 0
  name        = "${var.name}-${var.env}-bastion-bootstrap"
  description = "Minimal IAM permissions for bootstrap utilities running on the bastion instance"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeInstancesAndNLB"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "elasticloadbalancing:DescribeLoadBalancers"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMSendCommandForBootstrap"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "bastion_bootstrap" {
  count      = var.enable_bootstrap_tools ? 1 : 0
  role       = module.bastion.iam_role_name
  policy_arn = aws_iam_policy.bastion_bootstrap[0].arn
}

# 사용자가 추가로 주입한 IAM 정책(선택)
resource "aws_iam_role_policy_attachment" "extra" {
  for_each   = toset(var.iam_policy_arns)
  role       = module.bastion.iam_role_name
  policy_arn = each.value
}

# ec2-instance 모듈이 최소 출력만 제공하므로, 인스턴스 속성(public/private ip, AZ 등)은 data로 조회합니다.
data "aws_instance" "bastion" {
  instance_id = module.bastion.id
}
