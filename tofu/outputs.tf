output "server_ip" {
  description = "Frodo's public IPv4 address (SSH break-glass only)"
  value       = hcloud_server.frodo.ipv4_address
}

output "panel_url" {
  description = "Komodo panel URL (gated by Cloudflare Access)"
  value       = "https://komodo.raveh.dev"
}
