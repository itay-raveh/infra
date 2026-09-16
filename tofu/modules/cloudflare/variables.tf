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

variable "root_worker_source_dir" {
  type = string
}
