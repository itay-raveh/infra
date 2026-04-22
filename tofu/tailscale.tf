# https://registry.terraform.io/providers/tailscale/tailscale/latest/docs

resource "tailscale_dns_preferences" "this" {
  magic_dns = true
}

resource "tailscale_tailnet_settings" "this" {
  # LE certs on <host>.<tailnet>.ts.net, required for ingressClassName: tailscale.
  https_enabled = true
}

resource "tailscale_acl" "this" {
  # First apply on a tailnet with a default policy takes ownership without `terraform import`.
  overwrite_existing_content = true

  acl = jsonencode({
    tagOwners = {
      "tag:k8s-operator" = ["autogroup:admin"]
      "tag:k8s"          = ["tag:k8s-operator"]
    }
    acls = [
      { action = "accept", src = ["autogroup:member"], dst = ["autogroup:member:*"] },
      { action = "accept", src = ["autogroup:admin"], dst = ["tag:k8s:*"] },
      { action = "accept", src = ["tag:k8s-operator"], dst = ["tag:k8s:*"] },
    ]
    ssh = [
      {
        action = "check"
        src    = ["autogroup:member"]
        dst    = ["autogroup:self"]
        users  = ["autogroup:nonroot", "root"]
      },
    ]
  })
}

resource "tailscale_oauth_client" "k8s_operator" {
  description = "k8s operator (flux-managed)"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator"]
}
