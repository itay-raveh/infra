# Cloudflare

Account and zone IDs are in [tofu/locals.tf](../tofu/locals.tf).

## Managed in code

| Resource | Configuration |
|---|---|
| Tunnel, ingress, apex/wildcard DNS and redirects | [cloudflare.tf](../tofu/cloudflare.tf) |
| Root Worker | [root.tf](../tofu/root.tf) |
| Application Worker custom domains | [quizmon.tf](../tofu/quizmon.tf), [itay.tf](../tofu/itay.tf) |
| Application code, bindings and logs | Wrangler configuration in each application repo |
| Web Analytics | [web_analytics.tf](../tofu/web_analytics.tf) |
| Account MFA enforcement and admin memberships | [cloudflare_account.tf](../tofu/cloudflare_account.tf) |

After a Tunnel token change, run `mise run tunnel:refresh` and commit the
resulting Secret. See [deployment commands](deploying.md#refresh-generated-credentials).

## Managed in the dashboard

| Setting | Location |
|---|---|
| Personal MFA and recovery codes | My Profile > Authentication |
| TLS settings | Zone > SSL/TLS > Edge Certificates |
| DNSSEC | Zone > DNS > Settings |
| Budget alerts | Manage account > Notifications |
| Traffic overview | Analytics > Dashboards > Traffic overview |

TLS and DNSSEC have provider support but no resources in
`infra` yet. Provider 5.24.0 lacks the budget alert's dollar-spend fields and a
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
