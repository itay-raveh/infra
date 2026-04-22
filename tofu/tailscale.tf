# https://registry.terraform.io/providers/tailscale/tailscale/latest/docs

resource "tailscale_dns_preferences" "this" {
  magic_dns = true
}

resource "tailscale_tailnet_settings" "this" {
  # Enables Let's Encrypt cert provisioning on <host>.<tailnet>.ts.net
  # names; prerequisite for ingressClassName: tailscale in-cluster.
  https_enabled = true

  # Locks the admin-console policy editor to read-only against this repo
  # to prevent manual drift from the Terraform-managed ACL below.
  acls_externally_managed_on = true
  acls_external_link         = "https://github.com/itay-raveh/infra/blob/main/tofu/tailscale.tf"
}

resource "tailscale_acl" "this" {
  # Required on the very first apply against a tailnet that still has
  # Tailscale's default policy; takes ownership without requiring a
  # one-shot `terraform import`. Safe to keep on since this resource is
  # the sole source of truth going forward.
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

# OAuth client consumed by the in-cluster tailscale-operator. The client
# secret is returned only on Create; any -replace rotates it and requires
# re-running `mise run tailscale-operator:refresh-oauth` to re-sync the
# cluster Secret.
resource "tailscale_oauth_client" "k8s_operator" {
  description = "k8s operator (flux-managed)"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator"]
}
