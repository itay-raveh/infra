# Quizmon spending monitor

Flux deploys this monitor through the apps Kustomization. Its dedicated
Cloudflare token is stored in `secret.sops.yaml`, encrypted for the repository
recipients and the cluster. The token has account Billing Read and Workers KV
Storage Write, plus Zone WAF Write restricted to the game's zone.

Every five minutes, the CronJob reads account-wide billable usage and renews a
10-minute permission record consumed by Quizmon's Worker and reminder alarms.
At $1 of usage charges, it latches a pause in KV and enables the prepared firewall
rule for the Quizmon hostname. The subscription fee is excluded. Other Workers
in the account are not stopped by this monitor.

Cloudflare updates billing telemetry daily. This monitor does not implement an
account-wide hard spending cap. A monitoring API failure attempts both shutdown
mechanisms and leaves the Job failed for inspection. If the job stops running,
the Worker permission expires. A latched pause requires explicit recovery.

## Initial deployment or rebuild

Before the first scheduled check, run `node guard.mjs setup` and
`node guard.mjs resume` with the environment listed in `cronjob.yaml`.
Setup only creates a missing, disabled rule. Resume refuses when reported usage
charges are at or above the budget. An uninitialized permission record causes
`check` to pause the site.

Reconcile Flux and verify a scheduled Job succeeds and updates the KV permission
before deploying the matching Quizmon Worker safeguards. During an infrastructure
outage, the Worker permission expires after ten minutes.

## Inspect and recover

Use `kubectl -n quizmon-ops get jobs` and the selected Job's logs to inspect runs.
Run `node guard.mjs pause` with the configured environment for an emergency stop.
Run `node guard.mjs resume` only after resolving the cause. The scheduled `check`
command never clears a spending or manual shutdown.

The firewall rule blocks new requests to Quizmon, including new page loads.
Browser data is retained. Canceled reminder alarms retain their registration but
need a later registration request to schedule them again.

Tests: `node --test tests/cloudflare-spending-guard.test.mjs` from the infra root.
Manifests: `kubectl kustomize clusters/shire/apps/quizmon-spending-guard`.

References: [billing data freshness](https://blog.cloudflare.com/billable-usage-api/),
[billing API](https://developers.cloudflare.com/api/resources/billing/subresources/usage/methods/paygo/),
[KV consistency](https://developers.cloudflare.com/kv/concepts/how-kv-works/),
[Kubernetes CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/).
