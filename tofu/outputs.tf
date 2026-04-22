output "tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.shire.tunnel_token
  sensitive = true
}

output "public_ipv4" {
  value = module.talos.public_ipv4_list[0]
}

output "kubeconfig" {
  value     = module.talos.kubeconfig
  sensitive = true
}

output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}

output "talos_installer_image" {
  value = "factory.talos.dev/installer/${talos_image_factory_schematic.shire.id}:${local.talos_version}"
}

output "tailscale_operator_oauth_client_id" {
  value     = tailscale_oauth_client.k8s_operator.id
  sensitive = true
}

output "tailscale_operator_oauth_client_secret" {
  value     = tailscale_oauth_client.k8s_operator.key
  sensitive = true
}
