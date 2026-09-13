# Cloudflare

Account and zone IDs: [tofu/locals.tf](../tofu/locals.tf).

## Managed in code

| Resource | Configuration |
|---|---|
| Tunnel, ingress, apex/wildcard DNS, redirects, DNSSEC and minimum TLS | [cloudflare.tf](../tofu/cloudflare.tf) |
| Root Worker | [root.tf](../tofu/root.tf) |
| Application Worker domains | [quizmon.tf](../tofu/quizmon.tf), [itay.tf](../tofu/itay.tf) |
| Application code, bindings and logs | Each application's Wrangler config |
| Web Analytics | [web_analytics.tf](../tofu/web_analytics.tf) |
| MFA enforcement and memberships | [cloudflare_account.tf](../tofu/cloudflare_account.tf) |
| Tunnel, Universal SSL and Certificate Transparency alerts | [cloudflare_notifications.tf](../tofu/cloudflare_notifications.tf) |

After changing a Tunnel token, [refresh and commit its Secret](deploying.md#refresh-generated-credentials).
The default provider needs zone DNS, Zone Settings, SSL and Certificates,
Single Redirect, and Workers Routes write access, plus account Workers Scripts
and Zero Trust access. Administration and Web Analytics use a separate account
[token in SOPS](secrets.md#token-inventory).

## DNSSEC and TLS

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
| Other TLS settings | Zone > SSL/TLS > Edge Certificates |
| Budget alerts | Billing > Billable Usage to create; Notifications to edit |
| Traffic overview | Analytics > Dashboards > Traffic overview |

Provider 5.24.0 lacks dollar-spend fields for budget alerts and custom-dashboard
resources. Recheck its [schema](https://github.com/cloudflare/terraform-provider-cloudflare/tree/v5.24.0/docs/resources)
after upgrades.

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
