variable "env" {
  description = "환경 (dev/staging/prod)"
  type        = string
}

variable "project" {
  description = "프로젝트/조직 식별자"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "state_bucket" {
  description = "Terraform remote state S3 bucket"
  type        = string
}

variable "state_region" {
  description = "Terraform remote state S3 region"
  type        = string
}

variable "state_key_prefix" {
  description = "Terraform remote state key prefix"
  type        = string
}

variable "instance_type_postgres" {
  description = "PostgreSQL instance type"
  type        = string
  default     = "t3.medium"
}

variable "instance_type_neo4j" {
  description = "Neo4j instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "EC2 Key Pair name (Optional, null for Keyless)"
  type        = string
  default     = null
}

variable "postgres_password" {
  description = "Initial PostgreSQL Password"
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

variable "neo4j_password" {
  description = "Initial Neo4j Password"
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}
