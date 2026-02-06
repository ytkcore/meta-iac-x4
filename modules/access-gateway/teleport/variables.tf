# =============================================================================
# Teleport Access Gateway Module - Variables
# =============================================================================

variable "services" {
  description = "List of services to register as Teleport apps"
  type = list(object({
    name     = string
    uri      = string
    type     = string
    internal = bool
  }))
  default = []
}

variable "teleport_server" {
  description = "Teleport server information"
  type = object({
    instance_id  = string
    private_ip   = string
    cluster_name = string
    domain       = string
  })
}

variable "insecure_skip_verify" {
  description = "Skip TLS verification for backend services"
  type        = bool
  default     = true
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}
