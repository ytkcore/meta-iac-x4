# ==============================================================================
# AWS Load Balancer Controller — IAM Policy & Role Attachment
#
# Reference: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.8/deploy/installation/
# IAM Policy: https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.0/docs/install/iam_policy.json
# ==============================================================================

resource "aws_iam_policy" "albc" {
  name        = "${var.env}-${var.project}-albc-policy"
  description = "IAM policy for AWS Load Balancer Controller (NLB/ALB management)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EC2 & ELBv2: Describe resources
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:DescribeCoipPools",
          "ec2:GetCoipPoolUsage",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores"
        ]
        Resource = "*"
      },
      # IAM: Create/Delete service-linked role
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      # EC2: Manage Security Groups for LB
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup"
        ]
        Resource = "*"
      },
      # EC2: Manage tags
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "true"
          }
        }
      },
      # ELBv2: Manage Load Balancers
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "true"
          }
        }
      },
      # ELBv2: Manage Tags
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
      },
      # ELBv2: Modify resources
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "*"
      },
      # ELBv2: Manage Listeners & Rules
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      },
      # Cognito & ACM (for HTTPS listeners)
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project}-albc-policy"
  })
}

# Phase 1: Node IAM Role에 직접 부착
# Vault 전환 완료 후 자동 비활성화 (enable_vault_integration=true → count=0)
resource "aws_iam_role_policy_attachment" "albc" {
  count      = var.enable_vault_integration ? 0 : 1
  role       = var.node_iam_role_name
  policy_arn = aws_iam_policy.albc.arn
}

# ==============================================================================
# Phase 3: Vault AWS Secrets Engine — Dedicated ALBC IAM Role
#
# Vault가 Node IAM Role(EC2 metadata)로 이 Role을 AssumeRole하여
# ALBC Pod에 STS 임시 자격증명을 발급합니다.
# ==============================================================================

resource "aws_iam_role" "vault_albc" {
  count = var.enable_vault_integration ? 1 : 0
  name  = "${var.env}-${var.project}-vault-albc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.node_iam_role_name}"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name    = "${var.env}-${var.project}-vault-albc-role"
    Purpose = "Vault AWS Secrets Engine - ALBC"
  })
}

resource "aws_iam_role_policy_attachment" "vault_albc" {
  count      = var.enable_vault_integration ? 1 : 0
  role       = aws_iam_role.vault_albc[0].name
  policy_arn = aws_iam_policy.albc.arn
}

# Node Role에 STS AssumeRole 권한 추가 (Vault가 위 Role을 assume할 수 있게)
resource "aws_iam_role_policy" "vault_assume_albc" {
  count = var.enable_vault_integration ? 1 : 0
  name  = "${var.env}-${var.project}-vault-assume-albc"
  role  = var.node_iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.vault_albc[0].arn
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
