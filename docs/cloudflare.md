# Cloudflare

Account and zone IDs: [tofu/locals.tf](../tofu/locals.tf).

## Managed in code

| Resource | Configuration |
|---|---|
| Tunnel, ingress, apex/wildcard DNS, redirects, DNSSEC and minimum TLS | [cloudflare.tf](../tofu/cloudflare.tf) |
| Full (strict), HTTPS redirects, HTTPS rewrites and Universal SSL | [cloudflare_tls.tf](../tofu/cloudflare_tls.tf) |
| Root Worker | [root.tf](../tofu/root.tf) |
| Application Worker domains | [quizmon.tf](../tofu/quizmon.tf), [itay.tf](../tofu/itay.tf) |
| Application code, bindings and logs | Each application's Wrangler config |
| Web Analytics | [web_analytics.tf](../tofu/web_analytics.tf) |
| MFA enforcement and memberships | [cloudflare_account.tf](../tofu/cloudflare_account.tf) |
| Tunnel, Universal SSL and Certificate Transparency alerts | [cloudflare_notifications.tf](../tofu/cloudflare_notifications.tf) |
| SPF, Proton DKIM and DMARC records | [cloudflare_mail.tf](../tofu/cloudflare_mail.tf) |
| Bot and AI crawler settings | [cloudflare_bots.tf](../tofu/cloudflare_bots.tf) |
| Login rate limit | [cloudflare_rate_limits.tf](../tofu/cloudflare_rate_limits.tf) |

After changing a Tunnel token, [refresh and commit its Secret](deploying.md#refresh-generated-credentials).
The default provider needs zone DNS, Zone Settings, SSL and Certificates,
Single Redirect, WAF, and Workers Routes write access, plus account Workers Scripts
and Zero Trust access. Administration and Web Analytics use a separate account
[token in SOPS](secrets.md#token-inventory).

## DNSSEC and TLS

[cloudflare_tls.tf](../tofu/cloudflare_tls.tf) sets Full (strict) and keeps
Universal SSL, HTTP-to-HTTPS redirects and Automatic HTTPS Rewrites enabled.
[Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)
requires direct HTTPS origins to present a trusted, unexpired certificate that
matches the hostname. It does not change the [Tunnel service protocol](https://developers.cloudflare.com/tunnel/troubleshooting/https-origins/):
the connector still reaches Traefik over HTTP inside the cluster.

After applying, confirm **Full (strict)** under **SSL/TLS > Overview** and check
the Worker sites and Tunnel-backed application health endpoints. A direct
origin with an invalid certificate returns `526`. To roll back the mode, set
`cloudflare_zone_setting.ssl.value` to `"full"` and apply.

OpenTofu adopts existing settings through imports and configures DNSSEC and TLS
1.2 minimum. DNSSEC requires `DNS Write`; TLS requires `Zone Settings Write`.
Cloudflare Registrar publishes the parent DS record, which can take one to two
days. Verify publication and validation after applying:

```bash
dig @1.1.1.1 '<DOMAIN>' DS +dnssec
dig @1.1.1.1 '<HOSTNAME>' A +dnssec
curl --tlsv1.2 --tls-max 1.2 --head 'https://<HOSTNAME>'
```

Use the zone's domain and a proxied hostname. Expect a DS record, the `ad` flag
on the A response, and a successful TLS 1.2 connection. TLS 1.0/1.1 handshakes
should fail; first check that your test client supports them.
[TLS testing](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/#test-supported-tls-versions).

Roll back TLS by restoring `min_tls_version` and applying. For [DNSSEC rollback](https://developers.cloudflare.com/dns/dnssec/),
disable it at Registrar and wait for the parent DS TTL before removing zone
signing. Do not delete the OpenTofu resource first.

## Bots

[cloudflare_bots.tf](../tofu/cloudflare_bots.tf) keeps AI crawler blocking,
AI Labyrinth and managed `robots.txt` enabled. Bot Fight Mode stays off because
its domain-wide challenges can affect Wanderbound's API and uptime monitor.
Free Bot Fight Mode [cannot use WAF skip rules](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/#rules)
to exempt those requests.

The [provider resource](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.24.0/docs/resources/bot_management.md)
requires zone `Bot Management Read` for imports and `Bot Management Write` for
changes. Its import adopts the existing zone settings.

Under **Security > Settings > Block AI bots**, select **Mixed purpose crawlers
will continue to be allowed**. This opts out of the [September 2026 migration](https://developers.cloudflare.com/bots/additional-configurations/block-ai-bots/)
that extends training blocks to crawlers also used for search indexing.
Provider 5.24.0 does not expose `ai_bots_migration_opt_out`. Keep this preference
in the dashboard and verify it after applying bot settings or upgrading the provider.

## Login rate limit

[cloudflare_rate_limits.tf](../tofu/cloudflare_rate_limits.tf) adopts the zone's
existing rate-limiting ruleset. It matches Wanderbound's Google and Microsoft
login paths, including trailing slashes. Auth-state polling and uploads do not match.
Keep the rule's `ref` when importing or editing it to [preserve its ID](https://developers.cloudflare.com/terraform/troubleshooting/rule-id-changes/).

The initial threshold is 20 requests per 10 seconds, followed by a 10-second
block. [Free-plan limits](https://developers.cloudflare.com/waf/rate-limiting-rules/#availability)
allow one rule with path matching and IP counters. The same paths on every
proxied hostname count, regardless of HTTP method. Users sharing an IP share
the counter within each Cloudflare data center.

Applying requires zone `WAF Write`. Check **Security > Security rules > Rate
limiting rules**, test normal login, and review matching events under
**Security > Analytics** before lowering the threshold. To disable the rule,
set its `enabled` to `false` and apply.

## Mail

Incoming mail reaches Proton through Cloudflare Email Routing's catch-all.
Manage forwarding under **Email > Email Routing > Routing rules**. Cloudflare
owns the MX and forwarding DKIM records marked read-only in its API.

SPF, Proton DKIM and DMARC live in [cloudflare_mail.tf](../tofu/cloudflare_mail.tf).
The single SPF record authorizes Cloudflare forwarding and Proton sending.
Proton manages key rotation behind the three DNS-only DKIM CNAMEs. Get their
values from **Proton Mail > Settings > All settings > Domain names > Review**;
see [Proton's setup guide](https://proton.me/support/anti-spoofing-custom-domain).

Check published values after applying:

```bash
dig +short TXT '<DOMAIN>'
dig +short TXT '_dmarc.<DOMAIN>'
dig +short CNAME '<DKIM_HOSTNAME>'
```

Check that Proton's SPF and DKIM tabs show verified. Before tightening DMARC,
check a delivered message from each sender for `dmarc=pass` in its
`Authentication-Results` header. Keep `p=none` while reviewing reports under
**Email > DMARC Management**. Identify legitimate senders and check their aligned
SPF or DKIM results before enforcing a stricter policy. Report absence is not
evidence that every sender passes.

If authenticated mail reaches Gmail's Spam folder, save the received original
from the message's **More > Show original > Download original** menu.
For a known legitimate message, choose **Report not spam**, then send a fresh
test and check its folder. [Gmail's correction](https://support.google.com/mail/answer/1366858?hl=en)
applies to that recipient's mailbox; it does not verify delivery to other recipients.
Keep downloaded mail outside the repository.

Email Routing adoption is blocked by provider bugs
[#7301](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7301)
and [#7352](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7352).
The DNS resources do not use those affected resource types.

## Notifications

Alerts use `TF_VAR_cloudflare_proton_email`, the native Proton recovery address.

| Alert | Permission | Investigate |
|---|---|---|
| [Tunnel health](https://developers.cloudflare.com/tunnel/observability/) | Account `Notifications Write` or `Account Settings Write` | `shire` connector health; also check the application URL and connector logs |
| [Universal SSL](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/alerts/) | Same account permission | Validation and renewal failures; routine issuance and renewals also generate alerts |
| [Certificate Transparency](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/certificate-transparency-monitoring/) | Zone `SSL and Certificates Write` | Issuers and hostnames for certificates issued outside Cloudflare |

Tunnel health does not establish application availability. The first two alerts
use the `account` provider; CT uses the default zone provider.

After applying, verify enabled policies, recipients and the Tunnel filter under
**Manage account > Notifications**. CT's recipient is under **SSL/TLS > Edge
Certificates > Certificate Transparency Monitoring**. Pause any alert with
`enabled = false` and apply. Deleting CT's resource does not unsubscribe it in
provider 5.24.0.

## Managed in the dashboard

| Setting | Location |
|---|---|
| Personal MFA and recovery codes | My Profile > Authentication |
| Public security contact | Security > Settings > Web application exploits > Security.txt |
| Mixed-purpose crawler migration preference | Security > Settings > Block AI bots |
| Other TLS settings | Zone > SSL/TLS > Edge Certificates |
| Budget alerts | Billing > Billable Usage to create; Notifications to edit |
| Traffic overview | Analytics > Dashboards > Traffic overview |

Provider 5.24.0 lacks a security.txt resource, dollar-spend fields for budget
alerts and custom-dashboard resources. Recheck its [schema](https://github.com/cloudflare/terraform-provider-cloudflare/tree/v5.24.0/docs/resources)
after upgrades.

### Security contact

Manage [security.txt](https://developers.cloudflare.com/security-center/infrastructure/security-file/)
under **Security > Settings > Web application exploits > Security.txt > Configurations**.
Set **Contact** to `mailto:security@raveh.dev` and **Expires at** to
`2027-03-14T00:00:00Z`. Save, then enable the **Security.txt** switch.
The address receives mail through the existing Proton
catch-all. Before renewing, confirm the address still receives reports and
choose an expiry less than a year ahead, as [RFC 9116 recommends](https://www.rfc-editor.org/rfc/rfc9116.html#section-2.5.5).

Verify `/.well-known/security.txt` on each application hostname returns HTTP
200 with `Content-Type: text/plain`, the contact and the expiry. The apex
redirects to the same path on `itay.raveh.dev`. To remove it, select **Delete**
in its configuration.

### Budget alerts

[Budget alerts](https://developers.cloudflare.com/billing/manage/budget-alerts/)
cover account-wide usage-based spending, even when named “Quizmon.” They notify;
they do not stop spending. Check thresholds in the edit form. Retain the previous
threshold and recipients to reverse a change.

### Account access

Use `cloudflare@raveh.dev` (Administrator) daily. Gmail and native Proton logins
are Super Administrators for membership, billing and recovery. Their addresses
are `TF_VAR_cloudflare_primary_email`, `TF_VAR_cloudflare_gmail_email` and
`TF_VAR_cloudflare_proton_email` in `secrets/tofu.sops.yaml`.

[Enroll MFA](https://developers.cloudflare.com/fundamentals/user-profiles/2fa/)
separately in each profile under **My Profile > Authentication**. Save recovery
codes outside this repo and test fresh logins before closing working sessions.
OpenTofu requires all three accepted memberships with MFA before enforcing
account MFA. `prevent_destroy` protects the account and memberships and blocks
a full `tofu destroy`.

If domain mail fails, use Gmail or native Proton; if Proton fails, use Gmail.
Test recovery in a private window by opening **Members** and **Billing**.
Proton receives domain mail, including catch-all addresses. Manage sending
addresses under [Identity and addresses](https://proton.me/support/addresses-and-aliases).

### Traffic overview

Record each chart's dataset, measure, dimensions, filters and time range before
editing. These fields let you recreate it. Compare results with source analytics
for the same period.
