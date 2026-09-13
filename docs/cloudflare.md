# Cloudflare

Account and zone IDs are in [tofu/locals.tf](../tofu/locals.tf).

## Managed in code

| Resource | Configuration |
|---|---|
| Tunnel, ingress, apex/wildcard DNS and redirects | [cloudflare.tf](../tofu/cloudflare.tf) |
| DNSSEC and minimum TLS version | [cloudflare.tf](../tofu/cloudflare.tf) |
| Root Worker | [root.tf](../tofu/root.tf) |
| Application Worker custom domains | [quizmon.tf](../tofu/quizmon.tf), [itay.tf](../tofu/itay.tf) |
| Application code, bindings and logs | Wrangler configuration in each application repo |
| Web Analytics | [web_analytics.tf](../tofu/web_analytics.tf) |
| Account MFA enforcement and admin memberships | [cloudflare_account.tf](../tofu/cloudflare_account.tf) |
| Tunnel health and Universal SSL alerts | [cloudflare_notifications.tf](../tofu/cloudflare_notifications.tf) |

After a Tunnel token change, run `mise run tunnel:refresh` and commit the
resulting Secret. See [deployment commands](deploying.md#refresh-generated-credentials).

## DNSSEC and TLS

OpenTofu configures DNSSEC and a minimum TLS version of 1.2. Import blocks adopt
the existing zone settings. The Cloudflare token needs `DNS Write` and
`Zone Settings Write` for this zone.

Cloudflare Registrar publishes the DNSSEC DS record at the registry. Publication
can take one to two days. After applying, check the DNSSEC status and verify the
DS record and DNS validation before treating activation as complete.
[DNSSEC setup and rollback](https://developers.cloudflare.com/dns/dnssec/).

For verification, replace `<DOMAIN>` with the zone name and `<HOSTNAME>` with a
proxied application hostname:

```bash
dig @1.1.1.1 '<DOMAIN>' DS +dnssec
dig @1.1.1.1 '<HOSTNAME>' A +dnssec
curl --tlsv1.2 --tls-max 1.2 --head 'https://<HOSTNAME>'
```

The DNS responses should contain a DS record and the `ad` flag, respectively.
TLS 1.2 should connect; clients restricted to TLS 1.0 or 1.1 should fail the
handshake. Check that the test client itself supports those older versions.
[TLS verification](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/#test-supported-tls-versions).

To roll back TLS, restore the previous `min_tls_version` value and apply.
For DNSSEC rollback, disable it at Cloudflare Registrar and wait for the parent
DS TTL to expire before removing zone signing. Do not delete the OpenTofu
resource as the first rollback step.

## Notifications

[cloudflare_notifications.tf](../tofu/cloudflare_notifications.tf) sends Tunnel
health changes and Universal SSL certificate events to the native Proton
recovery address in `TF_VAR_cloudflare_proton_email`. It uses the `account`
provider. Its token needs `Notifications Write` or `Account Settings Write`.

The Tunnel alert covers `shire`. It reports connector health, so a healthy
tunnel does not prove that an application is reachable. Check the application
URL and connector logs when investigating an outage.
[Tunnel monitoring](https://developers.cloudflare.com/tunnel/observability/).

The SSL alert covers the account's Universal SSL certificates, including routine
issuance and renewal events. Investigate validation failures and certificates
that cannot renew.
[Certificate alerts](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/alerts/).

After applying, check **Manage account > Notifications** for both enabled
policies, the recipient, and the Tunnel filter. To pause an alert, set its
`enabled` field to `false` and apply.

## Managed in the dashboard

| Setting | Location |
|---|---|
| Personal MFA and recovery codes | My Profile > Authentication |
| Other TLS settings | Zone > SSL/TLS > Edge Certificates |
| Budget alerts | Manage account > Notifications |
| Traffic overview | Analytics > Dashboards > Traffic overview |

Provider 5.24.0 lacks the budget alert's dollar-spend fields and a
custom-dashboard resource. Recheck the [provider schema](https://github.com/cloudflare/terraform-provider-cloudflare/tree/v5.24.0/docs/resources)
after a version change.

### Budget alerts

Create alerts under **Manage account > Billing > Billable Usage**; edit existing
ones under **Manage account > Notifications**. Check the threshold in the edit
form, not the alert name.

Alerts cover account-wide usage-based spending, even if named “Quizmon.” They
send notifications and do not stop spending. Keep the previous threshold and
recipient list when editing a policy so the change can be reversed.
[Budget alert documentation](https://developers.cloudflare.com/billing/manage/budget-alerts/).

### Account access

Use `cloudflare@raveh.dev` with the Administrator role for daily work. The Gmail
and native Proton logins have Super Administrator access for membership changes,
billing and recovery.
Login addresses come from `TF_VAR_cloudflare_primary_email`,
`TF_VAR_cloudflare_gmail_email` and `TF_VAR_cloudflare_proton_email` in
`secrets/tofu.sops.yaml`.

Sign in to each profile separately, enroll MFA under **My Profile >
Authentication**, and save its recovery codes outside this repo. Test a fresh
login before closing the working session. OpenTofu requires all three
memberships to be accepted with MFA enabled before enforcing MFA for the account.
[Cloudflare enrollment instructions](https://developers.cloudflare.com/fundamentals/user-profiles/2fa/).

The account and memberships use `prevent_destroy`. A full `tofu destroy` stops
instead of removing them.

If domain mail fails, sign in with Gmail or the native Proton address. If Proton
is unavailable, use Gmail. In a private browser window, verify that the recovery
login opens the account's **Members** and **Billing** pages.

Proton receives domain mail, including catch-all addresses. Manage sending
addresses under Proton's **Identity and addresses**.
[Proton addresses](https://proton.me/support/addresses-and-aliases).

### Traffic overview

For each chart, retain the dataset, measure, dimensions, filters and time range
before editing it. Compare results with source analytics over the same period.
Those fields are also the information needed to recreate a dashboard manually.
