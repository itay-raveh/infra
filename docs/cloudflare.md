# Cloudflare

| Configuration | Owner |
|---|---|
| DNS, Tunnel, TLS, mail, account policies | [`tofu/modules/cloudflare/`](../tofu/modules/cloudflare/) |
| App domains, policies and private database connections | App-specific files in [`tofu/`](../tofu/) |
| Application Worker code, bindings and logs | Application repositories |
| Credentials and rotation | [Secrets](secrets.md) |

## Provider access

The default token manages zone DNS, settings, certificates, redirects, WAF, Worker routes and bots; account permissions cover Workers, Zero Trust, Connectivity Directory and Hyperdrive. The separate account token handles account administration, notifications, Web Analytics and account API tokens. Verify permissions against the resources being changed.

## Operational constraints

| Setting | Constraint |
|---|---|
| 0-RTT | Applications must reject unsafe early requests with `425`; disable [zero_rtt](../tofu/modules/cloudflare/tls.tf) before deploying incompatible code. |
| DNSSEC | Disable at the registrar and wait for the parent DS TTL before removing zone signing. [Rollback order](https://developers.cloudflare.com/dns/dnssec/#roll-back-dnssec). |
| Tunnel | Traefik receives HTTP inside the cluster, including under Full (strict). Refresh its Secret after token rotation. |
| Rate limits | Check each rule's hostname scope; IP/data-center counters share quotas across users behind NAT. |
| Alerts | Tunnel alerts cover connectors, not app availability. Universal SSL alerts include renewals. Disable Certificate Transparency alerts before deleting the resource; [provider deletion only forgets state](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.24.0/internal/services/ct_alerting/resource.go). |
| Bot Fight Mode | Off; domain-wide challenges affect APIs and [cannot be skipped by WAF rules](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/#rules). |

Leave `cf_robots_variant` unset in [bots.tf](../tofu/modules/cloudflare/bots.tf). The provider's `"off"` serialization has caused [inconsistent results](https://github.com/cloudflare/terraform-provider-cloudflare/issues/6727); verify the live value remains `"off"` after changes.

## Dashboard-managed settings

| Setting | Location / value |
|---|---|
| Mixed-purpose crawlers | Security → Settings → Block AI bots: allow mixed-purpose crawlers. [Migration](https://developers.cloudflare.com/bots/additional-configurations/block-ai-bots/). |
| Security contact | Security → Settings → Web application exploits → Security.txt. Renew before its configured expiry; test `/.well-known/security.txt`. |
| Budget alerts | Create in Billing → Billable Usage; edit in Notifications. Account-wide notifications, not spending caps. |
| Traffic overview | Analytics → Dashboards → Traffic overview. |
| Email catch-all | Email → Email Routing → Routing rules. Forwards to Proton. |

Email Routing owns MX and forwarding DKIM; [mail.tf](../tofu/modules/cloudflare/mail.tf) owns SPF, Proton DKIM and DMARC. Provider issues [#7301](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7301) and [#7352](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7352) prevent managing routing here. Before tightening DMARC, confirm aligned SPF/DKIM for legitimate senders in Email → DMARC Management.

## Account recovery

Daily access uses the domain Administrator account. Gmail and native Proton are Super Administrator recovery accounts; addresses are in `secrets/tofu.sops.yaml`. Test recovery access to Members and Billing, and keep MFA recovery codes outside this repo.

[account.tf](../tofu/modules/cloudflare/account.tf) requires accepted memberships and MFA before enforcement. Its `prevent_destroy` blocks a full OpenTofu destroy.
