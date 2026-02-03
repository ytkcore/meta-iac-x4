variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "env" {
  type = string
}

variable "project" {
  type = string
}

# name 제거 (locals 자동 생성)
# tags 제거 (locals 자동 생성)

# Remote state settings (shared via stacks/<env>/env.tfvars)
variable "state_bucket" {
  type        = string
  description = "Remote state S3 bucket (used by terraform_remote_state)."
  default     = null
}

variable "state_region" {
  type        = string
  description = "Remote state region (used by terraform_remote_state)."
  default     = null
}

variable "state_key_prefix" {
  type        = string
  description = "Remote state key prefix (used by terraform_remote_state)."
  default     = null
}

# Bastion settings
variable "bastion_subnet_key" {
  description = "Key in network stack output subnet_ids map. Bastion MUST be in a private subnet for jump host role."
  type        = string
  default     = "common-pri-a"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  description = "Optional AMI ID override."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root volume size (GiB)."
  type        = number
  default     = 20
}

variable "iam_path" {
  type        = string
  description = "IAM path for bastion instance role/profile."
  default     = "/"
}

variable "iam_permissions_boundary_arn" {
  type        = string
  description = "Optional permissions boundary ARN for the bastion role."
  default     = null
}

variable "iam_policy_arns" {
  type        = list(string)
  description = "Additional IAM policy ARNs to attach to the bastion role."
  default     = []
}

variable "attach_ssm_managed_policy" {
  type        = bool
  description = "Attach AmazonSSMManagedInstanceCore."
  default     = true
}

variable "allocate_eip" {
  type        = bool
  description = "Private Jump Server principle: No public IP. Set to false to disable EIP."
  default     = false
}

variable "eip_allocation_id" {
  type        = string
  description = "Existing EIP allocation id to associate (optional). If null and allocate_eip=true, a new EIP is created."
  default     = null
}

variable "azs" {
  type        = list(string)
  description = "Multi-AZ 사용 목록 (예: [\"ap-northeast-2a\",\"ap-northeast-2c\"]). env.tfvars에서 공통으로 주입됩니다."
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "bastion_security_group_id" {
  type        = string
  description = "Bastion에 적용할 SG ID를 외부에서 주입할 때 사용합니다. null이면 bastion 스택에서 기본 SG를 생성합니다."
  default     = null
}


# [NEW] base_domain (global variable compatibility)
variable "base_domain" {
  type        = string
  description = "Base domain (compatible with global env.tfvars)"
  default     = null

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.base_domain))
    error_message = "도메인 형식은 소문자, 숫자, 점(.), 하이픈(-)만 허용됩니다."
  }
}

variable "target_bucket_name" {
  type    = string
  default = ""
}

variable "longhorn_backup_bucket" {
  type    = string
  default = ""
}

variable "enable_gitops_apps" {
  type    = bool
  default = false
}

variable "gitops_apps_path" {
  type    = string
  default = ""
}

variable "gitops_repo_url" {
  type    = string
  default = ""
}

variable "gitops_ssh_key_path" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
