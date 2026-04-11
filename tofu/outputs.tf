# Consumed post-apply by `mise run tofu-secrets-sync` (§6.B step 4):
# the token is sops-encrypted into clusters/frodo/.../cloudflared/.
output "tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.frodo.tunnel_token
  sensitive = true
}

# Single CP node today; the module returns a list because the input shape
# allows >1. Index 0 is fine for a single-node cluster.
output "frodo_public_ipv4" {
  value = module.talos.public_ipv4_list[0]
}

# kubeconfig and talosconfig are written to local files by the mise
# tofu-apply task using `tofu output -raw`, then chmod 600. They are
# never committed (.gitignore covers them).
output "kubeconfig" {
  value     = module.talos.kubeconfig
  sensitive = true
}

output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}
