variable "name" {
  description = "WAF Web ACL name"
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN to associate with WAF"
  type        = string
}

variable "rate_limit" {
  description = "Rate limit (requests per 5 minutes from a single IP)"
  type        = number
  default     = 2000
}

variable "tags" {
  description = "Tags to apply to WAF resources"
  type        = map(string)
  default     = {}
}
