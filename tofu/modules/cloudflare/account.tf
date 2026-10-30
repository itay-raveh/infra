locals {
  administrator_role       = "05784afa30c1afe1440e79d9351c7430"
  super_administrator_role = "33666b9c79b9a5273fc7344ff42f953d"
  member_emails = {
    primary = var.primary_email
    gmail   = var.gmail_email
    proton  = var.proton_email
  }
}

resource "cloudflare_account_member" "admin" {
  provider = cloudflare.account
  for_each = {
    primary = local.administrator_role
    gmail   = local.super_administrator_role
    proton  = local.super_administrator_role
  }

  account_id = var.account_id
  email      = local.member_emails[each.key]
  roles      = [each.value]
  status     = "accepted"

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_account" "raveh_dev" {
  provider = cloudflare.account
  name     = "raveh.dev"

  settings = {
    enforce_twofactor = true
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition = alltrue([
        for member in cloudflare_account_member.admin :
        member.status == "accepted" && member.user.two_factor_authentication_enabled
      ])
      error_message = "Accept all three Cloudflare memberships and enable MFA on each login before enforcing account MFA."
    }
  }
}
