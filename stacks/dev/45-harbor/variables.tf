variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "env" {
  description = "Environment Name"
  type        = string
}

variable "project" {
  description = "Project Name"
  type        = string
}

variable "name" {
  description = "Resource name prefix (from env.tfvars)"
  type        = string
}

variable "tags" {
  description = "Common tags (not used by harbor-ec2 module today, kept to avoid tfvars warnings)"
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------------
# Remote state settings (shared via stacks/<env>/env.tfvars)
# ----------------------------------------------------------------------------
variable "state_bucket" {
  type        = string
  description = "Remote state S3 bucket (terraform_remote_state)."
  default     = null
}

variable "state_region" {
  type        = string
  description = "Remote state region (terraform_remote_state)."
  default     = null
}

variable "state_key_prefix" {
  type        = string
  description = "Remote state key prefix (terraform_remote_state)."
  default     = null
}

# ----------------------------------------------------------------------------
# Placement
# ----------------------------------------------------------------------------
variable "harbor_subnet_key" {
  description = "Key in 00-network output subnet_ids map where Harbor EC2 will be placed."
  type        = string
  default     = "common-private-c"
}

# ----------------------------------------------------------------------------
# EC2
# ----------------------------------------------------------------------------
variable "key_name" {
  description = "SSH Key Name (optional; SSM-only 권장)"
  type        = string
  default     = null
}

variable "instance_type" {
  description = "Instance Type"
  type        = string
  default     = "t3.large"
}

# ----------------------------------------------------------------------------
# Harbor App
# ----------------------------------------------------------------------------
variable "harbor_hostname" {
  description = "Harbor Service Domain"
  type        = string
  default     = "harbor.internal"
}

variable "harbor_version" {
  description = "Harbor Version"
  type        = string
  default     = "2.9.1"
}

variable "harbor_enable_tls" {
  description = "Enable TLS"
  type        = bool
  default     = false
}

variable "harbor_proxy_cache_project" {
  description = "Harbor proxy-cache project name (used by downstream stacks)"
  type        = string
  default     = "dockerhub-proxy"
}
# ----------------------------------------------------------------------------
# ALB / ACM
# ----------------------------------------------------------------------------
variable "alb_certificate_arn" {
  description = "ACM certificate ARN for Harbor ALB HTTPS listener (optional). If empty, only HTTP listener is created by this stack."
  type        = string
  default     = ""
}

variable "enable_alb" {
  description = "Whether to create an Application Load Balancer for Harbor"
  type        = bool
  default     = true
}


# ----------------------------------------------------------------------------
# S3 (Auto-injected by Makefile)
# ----------------------------------------------------------------------------
variable "target_bucket_name" {
  description = "S3 Bucket Name (Injected)"
  type        = string
}

variable "create_bucket" {
  description = "Create S3 Bucket Flag (Injected)"
  type        = bool
}

# ----------------------------------------------------------------------------
# Storage Configuration
# ----------------------------------------------------------------------------
variable "storage_type" {
  description = "Storage backend type (filesystem or s3)"
  type        = string
  default     = "filesystem"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 100
}

# ----------------------------------------------------------------------------
# Harbor Additional Settings
# ----------------------------------------------------------------------------
variable "admin_password" {
  description = "Harbor admin password"
  type        = string
  default     = "Harbor12345"
  sensitive   = true
}

variable "db_password" {
  description = "Harbor internal database password"
  type        = string
  default     = "root123"
  sensitive   = true
}

variable "create_proxy_cache" {
  description = "Whether to create Docker Hub proxy cache project"
  type        = bool
  # RKE2 설치/운영에서 외부 레지스트리 의존성을 줄이기 위해 기본 활성화
  default = true
}

# -----------------------------------------------------------------------------
# Helm Chart Seeding (OCI Registry)
# -----------------------------------------------------------------------------
variable "seed_helm_charts" {
  description = "Whether to download and push Helm charts to Harbor OCI registry for 55-bootstrap"
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version to seed"
  type        = string
  default     = "5.55.0"
}

variable "certmanager_chart_version" {
  description = "cert-manager Helm chart version to seed"
  type        = string
  default     = "v1.14.5"
}

variable "rancher_chart_version" {
  description = "Rancher Helm chart version to seed"
  type        = string
  default     = "2.10.10"
}

variable "seed_images" {
  description = "Whether to pre-pull and push seed images"
  type        = bool
  default     = false
}

variable "seed_postgres_tag" {
  description = "PostgreSQL image tag to seed"
  type        = string
  default     = ""
}

variable "seed_neo4j_tag" {
  description = "Neo4j image tag to seed"
  type        = string
  default     = ""
}

/*
variable "acm_cert_domain" {
  description = "검색할 ACM 인증서의 도메인 이름 (예: *.mymeta.net 또는 harbor.mymeta.net)"
  type        = string
}
*/

variable "base_domain" {
  description = "사용할 루트 도메인 (예: mymeta.net)"
  type        = string
  //  default     = "mymeta.net" # 여기에 본인의 도메인을 기본값으로 넣어두세요
}

variable "enable_route53_harbor_cname" {
  description = "Harbor ALB DNS를 Route53에 CNAME(harbor.<base_domain>)으로 자동 등록할지 여부"
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID (미지정 시 base_domain으로 자동 탐색)"
  type        = string
  default     = ""

  validation {
    condition     = !(var.enable_route53_harbor_cname && var.route53_zone_id == "")
    error_message = "enable_route53_harbor_cname=true requires route53_zone_id to be set (Hosted Zone not auto-discovered)."
  }
}

variable "route53_private_zone" {
  description = "자동 탐색 시 Private Hosted Zone을 사용할지 여부"
  type        = bool
  default     = false
}
