# https://registry.terraform.io/providers/tailscale/tailscale/latest/docs

resource "tailscale_dns_preferences" "this" {
  magic_dns = true
}

resource "tailscale_tailnet_settings" "this" {
  # https_enabled is tailnet-owner-only, not grantable via OAuth scope.
  acls_externally_managed_on = true
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
  description = "flux managed k8s operator"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator"]
}
