variable "project" {
  description = "프로젝트/조직 식별자"
  type        = string
}

variable "env" {
  description = "환경 (예: dev, prod)"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "name" {
  description = "리소스 네이밍 접두어"
  type        = string
  default     = "k8s"
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Golden Image Remote State
# -----------------------------------------------------------------------------
variable "state_bucket" {
  description = "Terraform remote state S3 bucket"
  type        = string
  default     = null
}

variable "state_region" {
  description = "Terraform remote state region"
  type        = string
  default     = null
}

variable "state_key_prefix" {
  description = "Terraform remote state key prefix"
  type        = string
  default     = null
}

variable "allow_ami_fallback" {
  description = "Allow fallback to default AMI if Golden Image not found"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (VPC 내부 접근 허용 범위)"
  type        = string
}

variable "private_subnet_ids" {
  description = "(Deprecated) Private Subnet ID 목록. control_plane_subnet_ids / worker_subnet_ids가 비어있을 때 fallback으로 사용합니다."
  type        = list(string)
  default     = []
}


variable "control_plane_subnet_ids" {
  description = "Control Plane용 Subnet ID 목록. 비어있으면 private_subnet_ids를 사용합니다."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.control_plane_subnet_ids) > 0 || length(var.private_subnet_ids) > 0
    error_message = "control_plane_subnet_ids 또는 private_subnet_ids 중 하나는 반드시 설정되어야 합니다."
  }
}

variable "worker_subnet_ids" {
  description = "Worker(Data Plane)용 Subnet ID 목록. 비어있으면 private_subnet_ids를 사용합니다."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.worker_subnet_ids) > 0 || length(var.private_subnet_ids) > 0
    error_message = "worker_subnet_ids 또는 private_subnet_ids 중 하나는 반드시 설정되어야 합니다."
  }
}

variable "os_family" {
  description = "노드 OS 선택 (기본: al2023). ubuntu2204는 user_data가 apt 기반으로 동작합니다."
  type        = string
  default     = "al2023"

  validation {
    condition     = contains(["al2023", "ubuntu2204"], var.os_family)
    error_message = "os_family는 al2023 또는 ubuntu2204만 허용합니다."
  }
}


variable "control_plane_count" {
  description = "Control Plane 노드 수"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Worker(Data Plane) 노드 수"
  type        = number
  default     = 4
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.large"
}

variable "root_volume_type" {
  description = "Root EBS 타입"
  type        = string
  default     = "gp3"
}

variable "root_volume_size_gb" {
  description = "Root EBS 크기(GB) - 개발망 최소 사양을 기본값으로 둡니다."
  type        = number
  default     = 30
}

##############################
# GPU Worker Nodes (Optional)
##############################
variable "gpu_worker_count" {
  description = "GPU Worker 노드 수 (0이면 GPU 노드 미생성)"
  type        = number
  default     = 0
}

variable "gpu_instance_type" {
  description = "GPU 인스턴스 타입 (NVIDIA GPU 탑재)"
  type        = string
  default     = "g4dn.xlarge"
}

variable "gpu_root_volume_size_gb" {
  description = "GPU 노드 Root EBS 크기(GB) — NVIDIA 드라이버 설치 공간 포함"
  type        = number
  default     = 50
}

variable "ami_id" {
  description = "원하는 AMI ID가 있다면 지정. 비워두면 Amazon Linux 2023 최신 AMI를 사용합니다."
  type        = string
  default     = null
}

variable "enable_internal_nlb" {
  description = "내부 NLB 생성 여부 (6443/9345) - 기본 true"
  type        = bool
  default     = true

  validation {
    condition     = var.enable_internal_nlb
    error_message = "현재 구현은 내부 NLB 사용(enable_internal_nlb=true)을 전제로 합니다. (9345/6443 엔드포인트 제공)"
  }
}

variable "rke2_version" {
  description = "설치할 RKE2 버전. Rancher 2.10.x(Stable) 호환: v1.28~v1.31"
  type        = string
  default     = "v1.31.6+rke2r1" # Rancher 2.10.x (stable) 호환 최신
}

variable "rke2_token" {
  description = "RKE2 클러스터 조인 토큰(선택). 비워두면 random으로 생성합니다."
  type        = string
  default     = null
  sensitive   = true
}

variable "extra_policy_arns" {
  description = "노드 IAM Role에 추가로 부착할 Managed Policy ARN 목록(선택)"
  type        = list(string)
  default     = []
}

variable "additional_security_group_ids" {
  description = "노드에 추가로 부착할 보안 그룹 ID 목록 (예: K8s Client SG)"
  type        = list(string)
  default     = []
}

variable "harbor_registry_hostport" {
  description = "Harbor registry host:port (예: harbor.internal:80)"
  type        = string
  default     = null
}

variable "harbor_hostname" {
  description = "Harbor hostname (예: harbor.dev.example.com). 값이 있으면 RKE2 노드에 /etc/hosts 매핑을 추가할 수 있습니다."
  type        = string
  default     = null
}

variable "harbor_private_ip" {
  description = "Harbor EC2 Private IP (harbor_hostname과 함께 /etc/hosts 매핑에 사용)"
  type        = string
  default     = null
}

variable "harbor_add_hosts_entry" {
  description = "harbor_hostname+harbor_private_ip가 주어졌을 때 /etc/hosts에 자동 매핑할지 여부"
  type        = bool
  default     = true
}

variable "harbor_scheme" {
  description = "Harbor scheme (http/https)"
  type        = string
  default     = "http"
}

variable "harbor_proxy_project" {
  description = "Harbor DockerHub proxy-cache project (rewrite 용도)"
  type        = string
  default     = "dockerhub-proxy"
}


variable "enable_image_prepull" {
  description = "Harbor Proxy Cache를 warm-up 하기 위해 RKE2 시스템 이미지 목록을 사전에 pull합니다(bootstrap server에서 1회 실행)."
  type        = bool
  default     = true
}

variable "image_prepull_source" {
  description = "이미지 목록(.txt) 다운로드 소스 (github|prime). github가 기본이며, 실패 시 prime로 fallback 합니다."
  type        = string
  default     = "github"
}

variable "disable_default_registry_fallback" {
  description = "true면 docker.io 등 기본 endpoint로 fall back 하지 않습니다(폐쇄망 강제)."
  type        = bool
  default     = false
}

variable "harbor_tls_insecure_skip_verify" {
  description = "harbor_scheme=https + self-signed일 때 TLS 검증 스킵"
  type        = bool
  default     = true
}

variable "harbor_auth_enabled" {
  description = "Harbor 인증 사용 여부 (private project 접근 시 필요)"
  type        = bool
  default     = false
}

variable "harbor_username" {
  description = "Harbor 인증 사용자명 (harbor_auth_enabled=true 시 필요)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "harbor_password" {
  description = "Harbor 인증 비밀번호 (harbor_auth_enabled=true 시 필요)"
  type        = string
  default     = ""
  sensitive   = true
}

##############################
# Public Ingress NLB (Optional)
##############################
variable "enable_public_ingress_nlb" {
  description = "Public NLB 생성 여부 (Ingress Controller용 443 (옵션: 80))"
  type        = bool
  default     = false
}
variable "enable_public_ingress_http_listener" {
  description = "Public Ingress NLB에서 HTTP(80) listener 생성 여부"
  type        = bool
  default     = false
}


variable "public_subnet_ids" {
  description = "Public NLB를 배치할 Public Subnet ID 목록"
  type        = list(string)
  default     = []
}

variable "ingress_http_nodeport" {
  description = "Nginx Ingress Controller HTTP NodePort (기본: 30080)"
  type        = number
  default     = 30080
}

variable "ingress_https_nodeport" {
  description = "Nginx Ingress Controller HTTPS NodePort (기본: 30443)"
  type        = number
  default     = 30443
}



variable "configure_ingress_nodeport" {
  description = "RKE2 built-in rke2-ingress-nginx chart에 HelmChartConfig를 주입하여 controller service(NodePort)를 보장합니다."
  type        = bool
  default     = true
}

variable "ingress_external_traffic_policy" {
  description = "Ingress controller Service externalTrafficPolicy. NLB 헬스체크 안정성을 위해 기본값 Cluster 권장 (Local/Cluster)."
  type        = string
  default     = "Cluster"

  validation {
    condition     = contains(["Cluster", "Local"], var.ingress_external_traffic_policy)
    error_message = "ingress_external_traffic_policy must be either 'Cluster' or 'Local'."
  }
}
##############################
# ACM TLS Termination (Optional)
##############################
variable "enable_acm_tls_termination" {
  description = <<-EOT
    NLB 레벨에서 AWS ACM을 사용한 TLS 종료 활성화.
    true로 설정하면:
    - NLB 443 리스너가 TLS로 동작 (ACM 인증서 사용)
    - 백엔드는 HTTP NodePort로 연결
    - Ingress Controller는 HTTP 모드로 동작
  EOT
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "AWS ACM 인증서 ARN (enable_acm_tls_termination=true 일 때 필수)"
  type        = string
  default     = null

  validation {
    condition     = var.acm_certificate_arn == null || can(regex("^arn:aws:acm:", var.acm_certificate_arn))
    error_message = "acm_certificate_arn must be a valid ACM certificate ARN"
  }
}

variable "acm_ssl_policy" {
  description = "NLB TLS 리스너에 적용할 SSL 정책"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06" # TLS 1.3 + TLS 1.2 권장
}

variable "enable_http_to_https_redirect" {
  description = "HTTP(80) → HTTPS(443) 리다이렉트 활성화 (ACM TLS 사용 시)"
  type        = bool
  default     = true
}

##############################
# AWS Cloud Controller Manager (CCM)
##############################
variable "enable_aws_ccm" {
  description = "AWS Cloud Controller Manager 자동 설치 여부"
  type        = bool
  default     = true
}

variable "aws_ccm_version" {
  description = "AWS CCM Helm 차트 버전"
  type        = string
  default     = "v1.31.0"
}

##############################
# Cilium CNI Configuration
##############################
variable "cni" {
  description = "CNI 플러그인 선택. canal(기본), cilium, none"
  type        = string
  default     = "canal"

  validation {
    condition     = contains(["canal", "cilium", "none"], var.cni)
    error_message = "cni는 canal, cilium, none 중 하나여야 합니다."
  }
}

variable "cilium_eni_mode" {
  description = "Cilium AWS ENI IPAM 모드 활성화 (true: Pod IP = VPC IP)"
  type        = bool
  default     = false
}

variable "cilium_enable_prefix_delegation" {
  description = "AWS ENI Prefix Delegation (/28 블록 할당) — Pod 밀도 향상"
  type        = bool
  default     = true
}

variable "cilium_enable_hubble" {
  description = "Hubble 네트워크 관측성 (relay + UI) 활성화"
  type        = bool
  default     = true
}

variable "cilium_kube_proxy_replacement" {
  description = "Cilium eBPF로 kube-proxy 완전 대체"
  type        = bool
  default     = true
}
