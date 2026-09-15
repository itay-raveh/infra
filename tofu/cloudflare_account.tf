locals {
  cloudflare_administrator_role       = "05784afa30c1afe1440e79d9351c7430"
  cloudflare_super_administrator_role = "33666b9c79b9a5273fc7344ff42f953d"
  cloudflare_member_emails = {
    primary = var.cloudflare_primary_email
    gmail   = var.cloudflare_gmail_email
    proton  = var.cloudflare_proton_email
  }
}

resource "cloudflare_account_member" "admin" {
  provider = cloudflare.account
  for_each = {
    primary = local.cloudflare_administrator_role
    gmail   = local.cloudflare_super_administrator_role
    proton  = local.cloudflare_super_administrator_role
  }

  account_id = local.cloudflare_account_id
  email      = local.cloudflare_member_emails[each.key]
  roles      = [each.value]
  status     = "accepted"

  lifecycle {
    prevent_destroy = true
  }
}

import {
  for_each = {
    primary = "7f524edc14fa71b31bf7354b3bfff2f8"
    gmail   = "5d5d854979ee59a29a9e0fac2bc56c61"
    proton  = "286c43f303932ef8b8e72e60f48c2682"
  }

  to = cloudflare_account_member.admin[each.key]
  id = "${local.cloudflare_account_id}/${each.value}"
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

import {
  to = cloudflare_account.raveh_dev
  id = local.cloudflare_account_id
}
