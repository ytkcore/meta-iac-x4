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

  ami_id           = var.ami_id
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size_gb
  user_data        = local.user_data

  # Golden Image State Configuration
  state_bucket       = var.state_bucket
  state_region       = var.state_region
  state_key_prefix   = var.state_key_prefix
  allow_ami_fallback = var.allow_ami_fallback
}
