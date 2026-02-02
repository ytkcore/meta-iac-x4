packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "al2023" {
  ami_name      = "meta-golden-image-al2023-{{timestamp}}"
  instance_type = "t3.medium"
  region        = "ap-northeast-2"
  
  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["137112412989"] # Amazon
  }
  
  ssh_username = "ec2-user"
  
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
      "sudo dnf update -y",
      "sudo dnf install -y docker jq curl wget git unzip",
      "sudo systemctl enable --now docker",
      "sudo usermod -aG docker ec2-user",
      
      # Install AWS CLI v2
      "curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\"",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "rm -rf awscliv2.zip aws/",
      
      # Verify SSM Agent (Pre-installed in AL2023, but ensuring it's enabled)
      "sudo systemctl enable --now amazon-ssm-agent",
      
      # Clean up
      "sudo dnf clean all"
    ]
  }
}
