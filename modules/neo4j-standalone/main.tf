locals {
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    neo4j_image_tag          = var.neo4j_image_tag
    neo4j_password           = var.neo4j_password
    neo4j_auth               = "neo4j/${var.neo4j_password}"
    harbor_registry_hostport = var.harbor_registry_hostport
    harbor_project           = var.harbor_project
    harbor_insecure          = tostring(var.harbor_insecure)
  })

  # Name Format: {env}-{project}-{workload}-{resource}-{suffix}
  name_prefix = "${var.env}-${var.project}-${var.name}"
}

resource "aws_security_group" "this" {
  name        = "${local.name_prefix}-sg"
  description = "Neo4j standalone SG"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_sg_ids) > 0 ? [1] : []
    content {
      description     = "Neo4j from allowed SGs"
      protocol        = "tcp"
      from_port       = 7474
      to_port         = 7474
      security_groups = var.allowed_sg_ids
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_sg_ids) > 0 ? [1] : []
    content {
      description     = "Neo4j Bolt from allowed SGs"
      protocol        = "tcp"
      from_port       = 7687
      to_port         = 7687
      security_groups = var.allowed_sg_ids
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Neo4j from allowed CIDRs"
      protocol    = "tcp"
      from_port   = 7474
      to_port     = 7474
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Neo4j Bolt from allowed CIDRs"
      protocol    = "tcp"
      from_port   = 7687
      to_port     = 7687
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-sg"
  })
}

module "instance" {
  source = "../ec2-instance"

  name                   = var.name
  env                    = var.env
  project                = var.project
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]

  # associate_public_ip    = false # ec2-instance 모듈에 이 변수가 없음 (기본값 확인 필요하나 보통 public subnet 아니면 false)
  # ec2-instance 모듈 코드를 보면 associate_public_ip_address 변수가 아예 없음. 
  # aws_instance 리소스는 subnet 설정 따름.

  ami_id = var.ami_id

  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size_gb
  user_data        = local.user_data

  # tags는 ec2-instance 모듈 내부에서 처리됨 (Name, Environment)
  # 만약 extra tags 지원한다면 추가해야 함. 현재 ec2-instance는 tags 변수 지원 안함.
}
