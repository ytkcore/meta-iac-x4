locals {
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    postgres_image_tag       = var.postgres_image_tag
    db_name                  = var.db_name
    db_username              = var.db_username
    db_password              = var.db_password
    harbor_registry_hostport = var.harbor_registry_hostport
    harbor_scheme            = var.harbor_scheme
    harbor_project           = var.harbor_project
    harbor_insecure          = var.harbor_insecure
  })
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-postgres-"
  description = "Postgres standalone SG"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_sg_ids) > 0 ? [1] : []
    content {
      description     = "Postgres from allowed SGs"
      protocol        = "tcp"
      from_port       = 5432
      to_port         = 5432
      security_groups = var.allowed_sg_ids
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Postgres from allowed CIDRs"
      protocol    = "tcp"
      from_port   = 5432
      to_port     = 5432
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-postgres-sg"
  })
}

module "instance" {
  source = "../ec2-instance"

  name                   = "${var.name}-postgres"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  associate_public_ip    = false

  ami_id = var.ami_id

  instance_type       = var.instance_type
  root_volume_size_gb = var.root_volume_size_gb
  user_data           = local.user_data

  tags = var.tags
}
