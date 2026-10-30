variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "tunnel_name" {
  type = string
}

variable "primary_email" {
  type      = string
  sensitive = true
}

variable "gmail_email" {
  type      = string
  sensitive = true
}

variable "proton_email" {
  type      = string
  sensitive = true
}

variable "rate_limit_rules" {
  type = list(object({
    ref         = string
    description = string
    expression  = string
    action      = string
    enabled     = bool
    ratelimit = object({
      characteristics     = list(string)
      period              = number
      requests_per_period = number
      mitigation_timeout  = number
      requests_to_origin  = bool
    })
  }))
}
