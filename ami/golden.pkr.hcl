packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

source "amazon-ebs" "al2023" {
  ami_name      = "meta-golden-image-al2023-{{timestamp}}"
  instance_type = "t3.medium"
  region        = "ap-northeast-2"

  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id

  # [STANDARD] SSM-only Management (No SSH Port 22 required)
  ssh_interface = "session_manager"
  communicator  = "ssh"
  ssh_username  = "ec2-user"
  associate_public_ip_address = true

  # [FIX] Use standard IAM Policy structure. Some versions require Statement to be a block, others an attribute.
  # We will use the block syntax but ensure the content is as simple as possible to avoid malformed errors.
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
  
  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["137112412989"] # Amazon
  }
  
  tags = {
    Name    = "meta-golden-image-al2023-{{timestamp}}"
    Role    = "meta-golden-image"
    Project = "meta"
    OS      = "AL2023"
  }
}

build {
  name = "meta-golden-packer"
  sources = [
    "source.amazon-ebs.al2023"
  ]

  provisioner "shell" {
    inline = [
      # 1. Package Update & Install (Resolving curl-minimal conflict in AL2023)
      "sudo dnf install -y --allowerasing curl",
      "sudo dnf update -y",
      "sudo dnf install -y docker jq wget git unzip",
      "sudo systemctl enable --now docker",
      "sudo usermod -aG docker ec2-user",
      
      # 2. Install AWS CLI v2
      "curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\"",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "rm -rf awscliv2.zip aws/",
      
      # 3. Security: Disable SSH Service (Pure SSM Only)
      "sudo systemctl stop sshd",
      "sudo systemctl disable sshd",
      "sudo systemctl mask sshd",
      
      # 4. Ensure SSM Agent is always active (Pre-installed in AL2023)
      "sudo systemctl enable --now amazon-ssm-agent",
      
      # 5. Clean up
      "sudo dnf clean all"
    ]
  }
}
