# Cloudflare

Use the [OpenTofu deployment workflow](deploying.md#change-cloud-infrastructure)
for settings managed in code. Account and zone IDs are in [locals.tf](../tofu/locals.tf).

## Managed in code

| Resource | Configuration |
|---|---|
| Tunnel and ingress | [tunnel.tf](../tofu/modules/cloudflare/tunnel.tf) |
| Apex/wildcard DNS and DNSSEC | [dns.tf](../tofu/modules/cloudflare/dns.tf) |
| TLS, HTTPS redirects/rewrites and Universal SSL | [tls.tf](../tofu/modules/cloudflare/tls.tf) |
| Root Worker, apex redirect and application Worker domains | [workers.tf](../tofu/modules/cloudflare/workers.tf) |
| Application code, bindings and logs | Each application's Wrangler config |
| Web Analytics | [analytics.tf](../tofu/modules/cloudflare/analytics.tf) |
| MFA enforcement and memberships | [account.tf](../tofu/modules/cloudflare/account.tf) |
| Tunnel, Universal SSL and Certificate Transparency alerts | [notifications.tf](../tofu/modules/cloudflare/notifications.tf) |
| SPF, Proton DKIM and DMARC records | [mail.tf](../tofu/modules/cloudflare/mail.tf) |
| Bot and AI crawler settings | [bots.tf](../tofu/modules/cloudflare/bots.tf) |
| Login rate limit | [rate_limits.tf](../tofu/modules/cloudflare/rate_limits.tf) |

[cloudflare.tf](../tofu/cloudflare.tf) calls the module. Providers,
[imports](../tofu/imports.tf) and [state-address moves](../tofu/moved.tf) stay
at the root. The module uses the existing state and deployment commands.

After changing a Tunnel token, [refresh and commit its Secret](deploying.md#refresh-generated-credentials).
The default provider needs zone DNS, Zone Settings, SSL and Certificates,
Single Redirect, WAF, and Workers Routes write access, plus account Workers Scripts
and Zero Trust access. Administration and Web Analytics use a separate account
[token in SOPS](secrets.md#token-inventory).

## DNSSEC and TLS

[Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)
requires direct HTTPS origins to present trusted, unexpired certificates matching
the hostname. An invalid certificate causes `526`. [Tunnel traffic](https://developers.cloudflare.com/tunnel/troubleshooting/https-origins/)
still reaches Traefik over HTTP inside the cluster. To roll back the SSL mode,
set `cloudflare_zone_setting.ssl.value` to `"full"` and apply.

[0-RTT](https://developers.cloudflare.com/speed/optimization/protocol/0-rtt-connection-resumption/)
is enabled. Wanderbound's API guard, added in 1.14.2, returns
[`425 Too Early`](https://www.rfc-editor.org/rfc/rfc8470.html#section-5.2)
before creating exports or consuming download tokens. Public pages accept early
requests. Keep the guard when changing routes. Before deploying an older release,
set `cloudflare_zone_setting.zero_rtt.value` to `"off"` and apply.

DNSSEC is enabled and minimum TLS is 1.2. Cloudflare Registrar publishes the
parent DS record, which can take one to two days. To test DNSSEC and TLS with a
proxied hostname:

```bash
dig @1.1.1.1 '<DOMAIN>' DS +dnssec
dig @1.1.1.1 '<HOSTNAME>' A +dnssec
curl --tlsv1.2 --tls-max 1.2 --head 'https://<HOSTNAME>'
```

Expect a DS record, an `ad` flag on the A response and a successful TLS 1.2
connection. [Test TLS 1.0/1.1 rejection](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/#test-supported-tls-versions)
only with a client that supports those versions.

To roll back minimum TLS, restore `min_tls_version` and apply. For
[DNSSEC rollback](https://developers.cloudflare.com/dns/dnssec/#roll-back-dnssec),
disable it at Registrar, then wait for the parent DS TTL to expire before
stopping zone signing. Deleting the OpenTofu resource first can break DNS resolution.

## Bots

AI crawler blocking, AI Labyrinth and managed `robots.txt` are enabled.
Bot Fight Mode is off: its domain-wide challenges can affect Wanderbound's API
and uptime monitor, with [no WAF skip rules](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/#rules)
to exempt them.

The [provider resource](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.24.0/docs/resources/bot_management.md)
requires zone `Bot Management Read` for imports and `Bot Management Write` for
changes.

Leave `cf_robots_variant` unset: provider 5.24.0 returns `null` after setting
`"off"`, causing [an inconsistent-result error](https://github.com/cloudflare/terraform-provider-cloudflare/issues/6727).
After bot changes, check this unmanaged field remains `"off"` with
[Get Zone Bot Management Config](https://developers.cloudflare.com/api/resources/bot_management/methods/get/).
The [mixed-purpose crawler preference](#mixed-purpose-crawlers) also needs a
manual check after bot changes or a provider upgrade.

## Login rate limit

The rule allows 20 requests per 10 seconds, then blocks for 10 seconds.
It matches Wanderbound's Google and Microsoft login paths, including trailing
slashes, on every proxied hostname and for any HTTP method. Auth-state polling
and uploads do not match. Users sharing an IP share a counter within each
Cloudflare data center. The [Free plan](https://developers.cloudflare.com/waf/rate-limiting-rules/#availability)
allows one rule with path matching and IP counters.

Preserve the rule's `ref` to [avoid replacing its ID](https://developers.cloudflare.com/terraform/troubleshooting/rule-id-changes/).
Before lowering the threshold, test normal login and review matching events
under **Security > Analytics**. To disable it, set `enabled = false` and apply.

## Mail

Incoming mail reaches Proton through Cloudflare Email Routing's catch-all.
Manage forwarding under **Email > Email Routing > Routing rules**. Cloudflare
owns the MX and forwarding DKIM records marked read-only in its API.

The single SPF record authorizes Cloudflare forwarding and Proton sending.
Proton manages key rotation behind the three DNS-only DKIM CNAMEs. Get their
values from **Proton Mail > Settings > All settings > Domain names > Review**;
see [Proton's setup guide](https://proton.me/support/anti-spoofing-custom-domain).

To inspect published mail records:

```bash
dig +short TXT '<DOMAIN>'
dig +short TXT '_dmarc.<DOMAIN>'
dig +short CNAME '<DKIM_HOSTNAME>'
```

Proton's SPF and DKIM tabs should show verified. DMARC uses `p=none`; review
reports under **Email > DMARC Management** before tightening it. For each
legitimate sender, check a delivered message's `Authentication-Results` for
`dmarc=pass` and aligned SPF or DKIM. Missing reports do not prove that mail passes.

For legitimate mail in Gmail's Spam folder, save **More > Show original >
Download original** outside the repo, choose [Report not spam](https://support.google.com/mail/answer/1366858?hl=en),
then send a fresh test. The correction applies only to that mailbox.

Email Routing adoption is blocked by provider bugs
[#7301](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7301)
and [#7352](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7352),
which do not affect the DNS resources above.

## Notifications

Alerts use `TF_VAR_cloudflare_proton_email`, the native Proton recovery address.

| Alert | Permission | Investigate |
|---|---|---|
| [Tunnel health](https://developers.cloudflare.com/tunnel/observability/) | Account `Notifications Write` or `Account Settings Write` | `shire` connector health; check application availability separately |
| [Universal SSL](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/alerts/) | Same account permission | Validation and renewal failures; routine issuance and renewals also generate alerts |
| [Certificate Transparency](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/certificate-transparency-monitoring/) | Zone `SSL and Certificates Write` | Issuers and hostnames for certificates issued outside Cloudflare |

Tunnel and Universal SSL alerts use the `account` provider; CT uses the default
zone provider. Disable alerts with `enabled = false` and apply. In provider
5.24.0, [deleting the CT resource](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.24.0/internal/services/ct_alerting/resource.go)
only removes it from state; it does not unsubscribe the recipient.

## Managed in the dashboard

Provider 5.24.0 lacks a security.txt resource, dollar-spend fields for budget
alerts and custom-dashboard resources. Recheck its [schema](https://github.com/cloudflare/terraform-provider-cloudflare/tree/v5.24.0/docs/resources)
after upgrades. TLS settings outside the files above remain under
**SSL/TLS > Edge Certificates**.

### Mixed-purpose crawlers

Under **Security > Settings > Block AI bots**, select **Mixed purpose crawlers
will continue to be allowed**. This opts out of the [September 2026 migration](https://developers.cloudflare.com/bots/additional-configurations/block-ai-bots/)
that extends training blocks to crawlers also used for search indexing.
Provider 5.24.0 does not expose `ai_bots_migration_opt_out`.

### Security contact

The [security.txt configuration](https://developers.cloudflare.com/security-center/infrastructure/security-file/)
is under **Security > Settings > Web application exploits > Security.txt > Configurations**:

| Field | Value |
|---|---|
| Contact | `mailto:security@raveh.dev` (Proton catch-all) |
| Expires at | `2027-03-14T00:00:00Z` |

To renew, test the contact address, set an expiry [less than a year ahead](https://www.rfc-editor.org/rfc/rfc9116.html#section-2.5.5),
save and enable **Security.txt**. Check `/.well-known/security.txt` on each app:
HTTP `200`, `Content-Type: text/plain`, correct contact and expiry. The apex
redirects to that path on `itay.raveh.dev`. Use **Delete** to remove the configuration.

### Budget alerts

Create [budget alerts](https://developers.cloudflare.com/billing/manage/budget-alerts/)
under **Billing > Billable Usage**; edit thresholds and recipients under
**Notifications**. They cover account-wide usage-based spending, even when
named “Quizmon,” and do not stop spending.

### Account access

Use `cloudflare@raveh.dev` (Administrator) daily. Gmail and native Proton are
Super Administrators for membership, billing and recovery. The three addresses
are stored in `secrets/tofu.sops.yaml` as `TF_VAR_cloudflare_primary_email`,
`TF_VAR_cloudflare_gmail_email` and `TF_VAR_cloudflare_proton_email`.

[Enroll MFA](https://developers.cloudflare.com/fundamentals/user-profiles/2fa/)
separately in each profile under **My Profile > Authentication**. Save recovery
codes outside this repo and test fresh logins before closing working sessions.
OpenTofu requires all three memberships accepted and MFA enabled before enforcing
account MFA. The account and memberships use `prevent_destroy`, which also
blocks a full `tofu destroy`.

If domain mail fails, use Gmail or native Proton; if Proton fails, use Gmail.
Test recovery in a private window by opening **Members** and **Billing**.
Add Proton sending addresses under [Identity and addresses](https://proton.me/support/addresses-and-aliases).

### Traffic overview

Edit **Analytics > Dashboards > Traffic overview**. Record each chart's dataset,
measure, dimensions, filters and time range so it can be recreated; compare it
with source analytics for the same period.
