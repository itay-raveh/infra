output "server_ip" {
  description = "Frodo's public IPv4 address"
  value       = hcloud_server.frodo.ipv4_address
}
