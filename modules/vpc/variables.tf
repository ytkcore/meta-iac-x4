variable "env" {
  type        = string
  description = "Environment name (e.g. dev, stg, prod)"
}

variable "project" {
  type        = string
  description = "Project name (e.g. meta)"
}

variable "region" {
  type        = string
  description = "AWS Region"
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones to deploy into"
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "subnets" {
  description = "Optional override for Subnet definitions. If null, dynamic calculation is used."
  type = map(object({
    cidr   = string
    az     = string
    tier   = string # public | common | k8s_cp | k8s_dp | db
    public = bool
  }))
  default = null
}

variable "enable_nat" {
  type        = bool
  description = "If true, create NAT gateways and private route default via NAT."
  default     = true
}

variable "enable_nat_for_db" {
  type        = bool
  description = "If true, add default route via NAT to DB route tables."
  default     = true
}

variable "enable_gateway_endpoints" {
  type        = bool
  description = "Create Gateway VPC Endpoints for S3/DynamoDB."
  default     = true
}

variable "gateway_services" {
  type        = list(string)
  description = "List of services for Gateway Endpoints."
  default     = ["s3", "dynamodb"]
}

# Interface VPC Endpoints (SSM, etc.)
variable "enable_interface_endpoints" {
  type        = bool
  description = "If true, create Interface VPC Endpoints for management (SSM)."
  default     = false
}

variable "interface_services" {
  type        = list(string)
  description = "List of services for Interface Endpoints (e.g. ssm, ssmmessages)."
  default     = ["ssm", "ssmmessages", "ec2messages"]
}

variable "interface_subnet_tiers" {
  type        = list(string)
  description = "List of subnet tiers where Interface Endpoints will be placed."
  default     = ["db", "common"]
}

variable "kubernetes_cluster_name" {
  type        = string
  description = "The name of the Kubernetes cluster for cloud-provider tagging. If provided, subnets will be tagged."
  default     = ""
}
