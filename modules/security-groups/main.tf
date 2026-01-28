# Bastion
resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion"
  description = "Bastion access (SSM-only, no inbound)"
  vpc_id      = var.vpc_id

  # SSM-only: No inbound rules. Access is via AWS Systems Manager Session Manager.
  # If you need SSH for break-glass, create a separate temporary SG and attach manually.

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-bastion" })
}


# Break-glass SG (no inbound by default). Attach temporarily during emergency to enable SSH from a restricted CIDR.
resource "aws_security_group" "breakglass_ssh" {
  name        = "${var.name}-breakglass-ssh"
  description = "Break-glass SSH (NO inbound by default; attach temporarily)"
  vpc_id      = var.vpc_id

  # No ingress by default (intentionally empty).
  # During emergency, add a temporary ingress rule manually (22/tcp from a single /32) and attach to the instance ENI.

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-breakglass-ssh" })
}
# Public LB (instance target)
resource "aws_security_group" "lb_public" {
  name        = "${var.name}-lb-public"
  description = "Public LB SG (instance target)"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.lb_ports
    content {
      description = "TCP ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.lb_ingress_cidrs
    }
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-lb-public" })
}

# Self-managed K8s Control Plane
resource "aws_security_group" "k8s_cp" {
  name        = "${var.name}-k8s-cp"
  description = "Self-managed K8s control plane"
  vpc_id      = var.vpc_id

  # K8s API from admins + VPC
  ingress {
    description = "K8s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = distinct(concat(var.admin_cidrs, [var.vpc_cidr]))
  }

  # RKE2 server port (agents connect)
  ingress {
    description = "RKE2 server"
    from_port   = 9345
    to_port     = 9345
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # etcd only from control-plane SG
  ingress {
    description     = "etcd"
    from_port       = 2379
    to_port         = 2380
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_cp.id]
  }

  # kubelet (from workers or cp)
  ingress {
    description = "kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-k8s-cp" })
}

# Self-managed K8s Workers
resource "aws_security_group" "k8s_worker" {
  name        = "${var.name}-k8s-worker"
  description = "Self-managed K8s worker nodes"
  vpc_id      = var.vpc_id

  # Node-to-node (overlay/CNI)
  ingress {
    description = "Node-to-node"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # kubelet from control plane
  ingress {
    description     = "kubelet from cp"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_cp.id]
  }

  # Service ports from public LB (instance target)
  dynamic "ingress" {
    for_each = toset(var.lb_to_worker_tcp_ports)
    content {
      description     = "LB -> worker tcp ${ingress.value}"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.lb_public.id]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_nodeport_from_lb ? [1] : []
    content {
      description     = "NodePort from LB"
      from_port       = var.nodeport_from
      to_port         = var.nodeport_to
      protocol        = "tcp"
      security_groups = [aws_security_group.lb_public.id]
    }
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-k8s-worker" })
}

# DB
resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "DB access from workers (and optional bastion)"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = toset(var.db_ports)
    content {
      description     = "DB port ${ingress.value} from workers"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.k8s_worker.id]
    }
  }

  dynamic "ingress" {
    for_each = var.allow_db_from_bastion ? toset(var.db_ports) : []
    content {
      description     = "DB port ${ingress.value} from bastion"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.bastion.id]
    }
  }

  egress {
    description = "VPC egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, { Name = "${var.name}-db" })
}

# Interface VPC Endpoint SG
resource "aws_security_group" "vpce" {
  name        = "${var.name}-vpce"
  description = "Interface VPC endpoints SG"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-vpce" })
}
