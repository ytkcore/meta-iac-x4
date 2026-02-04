# =============================================================================
# Golden Image Packer Template
# Amazon Linux 2023 + Docker + SSM + CloudWatch + Teleport
# =============================================================================

packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "ami_name_prefix" {
  type    = string
  default = "meta-golden-image-al2023"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_username" {
  type    = string
  default = "ec2-user"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "tags" {
  type = map(string)
  default = {
    ManagedBy = "packer"
    Project   = "meta"
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "amazon-ami" "al2023" {
  filters = {
    name                = "al2023-ami-*-kernel-*-x86_64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}

# -----------------------------------------------------------------------------
# Source (Builder)
# -----------------------------------------------------------------------------
source "amazon-ebs" "golden" {
  ami_name        = "${var.ami_name_prefix}-{{timestamp}}"
  ami_description = "Golden Image - Amazon Linux 2023 with Docker, SSM, CloudWatch, Teleport"
  instance_type   = var.instance_type
  region          = var.aws_region
  source_ami      = data.amazon-ami.al2023.id
  
  # Use SSM instead of SSH (works in private subnets)
  ssh_interface = "session_manager"
  communicator  = "ssh"
  ssh_username  = var.ssh_username

  # VPC/Subnet
  vpc_id    = var.vpc_id != "" ? var.vpc_id : null
  subnet_id = var.subnet_id != "" ? var.subnet_id : null

  # Public IP for SSM connectivity
  associate_public_ip_address = true

  # Temporary IAM policy for SSM access during build
  temporary_iam_instance_profile_policy_document {
    Version = "2012-10-17"
    Statement {
      Effect   = "Allow"
      Action   = [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = ["*"]
    }
  }

  # IMDSv2 required
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Tags
  tags = merge(var.tags, {
    Name        = "${var.ami_name_prefix}-{{timestamp}}"
    BuildTime   = "{{timestamp}}"
    SourceAMI   = "{{ .SourceAMI }}"
    Environment = "golden"
    Role        = "meta-golden-image"
  })

  run_tags = merge(var.tags, {
    Name = "packer-builder-golden-image"
  })

  # Encryption
  encrypt_boot = true

  # Cleanup
  force_deregister      = false
  force_delete_snapshot = false
}

# -----------------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------------
build {
  name    = "golden-image"
  sources = ["source.amazon-ebs.golden"]

  # 1. System Update
  provisioner "shell" {
    inline = [
      "echo '=== Updating System ==='",
      "# Fix curl-minimal conflict in AL2023",
      "sudo dnf install -y --allowerasing curl",
      "sudo dnf update -y",
      "sudo dnf install -y docker jq wget git unzip"
    ]
  }

  # 2. Docker Installation
  provisioner "shell" {
    inline = [
      "echo '=== Installing Docker ==='",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ec2-user"
    ]
  }

  # 3. AWS CLI v2
  provisioner "shell" {
    inline = [
      "echo '=== Installing AWS CLI v2 ==='",
      "cd /tmp",
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'",
      "unzip -q awscliv2.zip",
      "sudo ./aws/install --update",
      "rm -rf aws awscliv2.zip"
    ]
  }

  # 4. SSM Agent (pre-installed on AL2023, ensure enabled)
  provisioner "shell" {
    inline = [
      "echo '=== Configuring SSM Agent ==='",
      "sudo systemctl enable amazon-ssm-agent",
      "sudo systemctl start amazon-ssm-agent || true"
    ]
  }

  # 5. CloudWatch Agent
  provisioner "shell" {
    inline = [
      "echo '=== Installing CloudWatch Agent ==='",
      "sudo dnf install -y amazon-cloudwatch-agent",
      "# Agent will be configured via user-data at runtime",
      "# Default: disabled for cost optimization"
    ]
  }

  # 6. Teleport Agent (binary only, configured at runtime)
  provisioner "shell" {
    inline = [
      "echo '=== Installing Teleport Agent ==='",
      "TELEPORT_VERSION=14.3.3",
      "cd /tmp",
      "curl -fsSL https://cdn.teleport.dev/teleport-v$${TELEPORT_VERSION}-linux-amd64-bin.tar.gz -o teleport.tar.gz",
      "tar -xzf teleport.tar.gz",
      "sudo mv teleport/tctl teleport/tsh teleport/teleport /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/teleport /usr/local/bin/tctl /usr/local/bin/tsh",
      "rm -rf teleport teleport.tar.gz",
      "",
      "# Create teleport user and directories",
      "sudo useradd -r -s /sbin/nologin teleport || true",
      "sudo mkdir -p /etc/teleport /var/lib/teleport",
      "sudo chown teleport:teleport /var/lib/teleport"
    ]
  }

  # 7. SSH Hardening
  provisioner "shell" {
    inline = [
      "echo '=== Hardening SSH ==='",
      "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config",
      "# SSH port is configured at runtime via user-data"
    ]
  }

  # 8. SELinux (keep enforcing)
  provisioner "shell" {
    inline = [
      "echo '=== Verifying SELinux ==='",
      "getenforce || echo 'SELinux not available'",
      "sudo sestatus || true"
    ]
  }

  # 9. Cleanup
  provisioner "shell" {
    inline = [
      "echo '=== Cleanup ==='",
      "sudo dnf clean all",
      "sudo rm -rf /var/cache/dnf",
      "sudo rm -rf /tmp/*",
      "sudo rm -f /root/.bash_history",
      "history -c"
    ]
  }

  # Post-processor: manifest for Terraform integration
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
