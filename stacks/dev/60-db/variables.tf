variable "env" {
  type        = string
  description = "Environment name (e.g., dev/prod)."
}

variable "project" {
  type        = string
  description = "Project/service name."
}

variable "region" {
  type        = string
  default     = "ap-northeast-2"
  description = "AWS region."
}

variable "state_bucket" {
  type        = string
  description = "Remote state bucket name."
}

variable "state_region" {
  type        = string
  default     = "ap-northeast-2"
  description = "Remote state bucket region."
}

variable "state_key_prefix" {
  type        = string
  description = "Remote state key prefix (folder-like)."
}

variable "azs" {
  type        = list(string)
  description = "Multi-AZ list (e.g., [\"ap-northeast-2a\",\"ap-northeast-2c\"])."
}

# Postgres mode: self (EC2), rds (RDS instance), aurora (Aurora PostgreSQL)
variable "postgres_mode" {
  type        = string
  default     = "self"
  description = "Postgres deployment mode: self | rds | aurora. Default: self."
  validation {
    condition     = contains(["self", "rds", "aurora"], var.postgres_mode)
    error_message = "postgres_mode must be one of: self, rds, aurora."
  }
}

variable "db_subnet_tier" {
  type        = string
  default     = "db"
  description = "Subnet tier to place DB instances in. Default: db."
}

variable "db_instance_type" {
  type        = string
  default     = "t3.large"
  description = "EC2 instance type for standalone DBs."
}

variable "db_root_volume_gb" {
  type        = number
  default     = 50
  description = "Root volume size (GiB) for standalone DBs."
}

variable "postgres_image_tag" {
  type        = string
  default     = "18.1"
  description = "Docker image tag for postgres (e.g., 18.1)."
}

variable "postgres_db_name" {
  type        = string
  default     = "app"
  description = "Default database name."
}

variable "postgres_username" {
  type        = string
  default     = "app"
  description = "Default database username."
}

variable "postgres_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "If null, Terraform will generate a random password."
}

variable "neo4j_image_tag" {
  type        = string
  default     = "5.26.19"
  description = "Docker image tag for neo4j (e.g., 5.26.19)."
}

variable "neo4j_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "If null, Terraform will generate a random password."
}

variable "require_rke2_state" {
  type        = bool
  default     = true
  description = "If true, this stack requires 50-rke2 state to exist to restrict DB ingress from node SG."
}

# Managed Postgres (RDS/Aurora) settings
variable "rds_instance_class" {
  type        = string
  default     = "db.t4g.micro"
  description = "RDS instance class when postgres_mode=rds."
}

variable "rds_engine_version" {
  type        = string
  default     = "18.1"
  description = "RDS PostgreSQL engine version when postgres_mode=rds."
}

variable "aurora_engine_version" {
  type        = string
  default     = "17.7"
  description = "Aurora PostgreSQL engine version when postgres_mode=aurora."
}

variable "aurora_instance_class" {
  type        = string
  default     = "db.t4g.medium"
  description = "Aurora instance class for the single writer instance."
}

variable "backup_retention_days" {
  type        = number
  default     = 1
  description = "Backup retention days for managed DB (dev-friendly default: 1)."
}
