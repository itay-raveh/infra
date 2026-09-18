# Cloudflare

Configuration lives in [tofu/modules/cloudflare](../tofu/modules/cloudflare/).
Use the [deployment workflow](deploying.md#change-cloud-infrastructure) and
[token inventory](secrets.md#token-inventory). Application Worker code, bindings
and logs belong to each application's Wrangler config.

## Token permissions

The default provider needs zone DNS, Zone Settings, SSL and Certificates,
Single Redirect, WAF, Workers Routes and Bot Management write access, plus
account Workers Scripts and Zero Trust access. Bot imports need Bot Management Read.
The separate account token handles administration, Web Analytics and notifications
(`Notifications Write` or `Account Settings Write`).

## Operational constraints

- **0-RTT** depends on Wanderbound's API guard from 1.14.2, which rejects early
  requests with `425` before creating exports or consuming download tokens.
  Disable `zero_rtt` in [tls.tf](../tofu/modules/cloudflare/tls.tf) before
  deploying a release without that guard.
- **DNSSEC rollback:** disable DNSSEC at Registrar, then wait for the parent DS
  TTL to expire before stopping zone signing. Reversing this order
  [can break DNS resolution](https://developers.cloudflare.com/dns/dnssec/#roll-back-dnssec).
- **Tunnel:** Traefik receives HTTP inside the cluster even with Full (strict).
  After token rotation, [refresh its Kubernetes Secret](deploying.md#refresh-generated-credentials).
- **Login rate limiting:** [counters](../tofu/modules/cloudflare/rate_limits.tf)
  are per IP and Cloudflare data center. Users behind one NAT share a quota.
- **Alerts** go to the native Proton recovery address. Tunnel alerts cover
  connectors, not application availability. Universal SSL includes routine renewals.
  To stop Certificate Transparency alerts, apply `enabled = false` before removing the
  resource: provider 5.24.0's [delete only forgets state](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.24.0/internal/services/ct_alerting/resource.go).

## Bots

Bot Fight Mode stays off because its domain-wide challenges affect APIs and
monitors, and [cannot be skipped by WAF rules](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/#rules).

Leave `cf_robots_variant` unset in [bots.tf](../tofu/modules/cloudflare/bots.tf).
Provider 5.24.0 turns `"off"` into `null`, producing
[an inconsistent-result error](https://github.com/cloudflare/terraform-provider-cloudflare/issues/6727).
After bot changes or provider upgrades, check the two unmanaged values:
`cf_robots_variant = "off"` through the
[API](https://developers.cloudflare.com/api/resources/bot_management/methods/get/),
and the mixed-purpose crawler preference below.

## Mail

Cloudflare Email Routing forwards the catch-all to Proton and owns the read-only
MX and forwarding DKIM records. [mail.tf](../tofu/modules/cloudflare/mail.tf)
owns SPF, Proton DKIM and DMARC. SPF must authorize both forwarding and sending.

Before tightening DMARC from `p=none`, review **Email > DMARC Management** and
confirm delivered mail from every legitimate sender has `dmarc=pass` with aligned
SPF or DKIM. Email Routing remains outside OpenTofu because of provider bugs
[#7301](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7301) and
[#7352](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7352).

## Dashboard settings

Provider 5.24.0 does not expose these settings:

| Setting | Location and configuration |
|---|---|
| Mixed-purpose crawlers | **Security > Settings > Block AI bots**: select **Mixed purpose crawlers will continue to be allowed** to preserve search indexing under the [September 2026 migration](https://developers.cloudflare.com/bots/additional-configurations/block-ai-bots/). |
| Security contact | **Security > Settings > Web application exploits > Security.txt > Configurations**: `mailto:security@raveh.dev`, expires `2027-03-14T00:00:00Z`. |
| Budget alerts | Create under **Billing > Billable Usage**; edit under **Notifications**. Alerts cover account-wide usage-based spending, even when named “Quizmon.” They do not cap spending. |
| Traffic overview | **Analytics > Dashboards > Traffic overview**. |

Renew security.txt with a tested contact address and expiry
[less than a year ahead](https://www.rfc-editor.org/rfc/rfc9116.html#section-2.5.5).
Verify `/.well-known/security.txt` returns `200`, `text/plain` and the new values
on each app. The apex redirects to `itay.raveh.dev`.

Manage the mail catch-all under **Email > Email Routing > Routing rules**.

## Account access

Use `cloudflare@raveh.dev` (Administrator) daily. Gmail and native Proton are
Super Administrators for membership, billing and recovery. Addresses are in
`secrets/tofu.sops.yaml`. If domain mail fails, use either backup; if Proton
fails, use Gmail.

Enroll MFA on each login and store recovery codes outside the repo.
[account.tf](../tofu/modules/cloudflare/account.tf) requires accepted memberships
and MFA before enforcement. Its `prevent_destroy` also blocks a full `tofu destroy`.
Test recovery logins in a private window with access to **Members** and **Billing**.
