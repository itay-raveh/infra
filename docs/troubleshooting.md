# Troubleshooting

Symptoms-first guide for the shire cluster. Find your symptom, run the
commands.

---

## Site is down

Work through this top-to-bottom. Stop at the first failure.

```
# 1. Is the node alive?
talosctl health

# 2. Is Kubernetes running?
mise run nodes

# 3. Is Flux healthy?
flux get kustomizations

# 4. Any pods in a bad state?
mise run unhealthy

# 5. Check the failing layer (tunnel, traefik, or app)
mise run klogs -- -n cloudflared deploy/cloudflared-cloudflared
mise run klogs -- -n traefik deploy/traefik
mise run klogs -- -n wanderbound deploy/wanderbound-app
```

If the node itself is unreachable, check the management tunnel first:

```
sudo wg show shire
mise run wireguard:configure
ping -c 3 10.200.0.1
```

A recent handshake with no private API response points to the node or
Talos. No handshake points to the UDP 51820 firewall rule, server
endpoint, or peer keys. If the server was deleted or replaced, follow
the rebuild path in `setup.md`. If its WireGuard machine configuration
was lost, follow the break-glass procedure in `disaster-recovery.md`.

The Hetzner module configures the physical links as `eth0` and `eth1`.
If `talosctl get links` instead shows predictable names such as
`enp1s0`, verify that `talosctl get cmdline` contains `net.ifnames=0`.
The repository pins that argument in `tofu/main.tf`. Apply the active
machine configuration and perform a normal Talos upgrade to repair an
older boot that was installed with the wrong platform defaults.

---

## Flux not reconciling

```
# What's stuck?
mise run flux:unhealthy

# Force a full sync from git
mise run reconcile

# Suspend + resume a stuck resource
flux suspend kustomization infrastructure
flux resume kustomization infrastructure

# If a HelmRelease is stuck in "upgrade retries exhausted"
flux suspend hr <name> -n flux-system
flux resume hr <name> -n flux-system

# Or force-sync a single resource
mise run flux:sync-hr -- -n flux-system <name>
mise run flux:sync-ks -- infrastructure
```

Check the source is reachable:

```
flux get sources git -A
flux get sources helm -A
```

If Flux can't decrypt SOPS secrets, the `sops-age` Secret may be
missing or stale. Re-seed it:

```
sops --decrypt bootstrap/cluster-age-key.sops.txt \
  | kubectl create secret generic sops-age \
      -n flux-system \
      --from-file=age.agekey=/dev/stdin \
      --dry-run=client -o yaml | kubectl apply -f -
```

---

## Pod stuck in CrashLoopBackOff

```
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --previous
```

For the Wanderbound app, common causes:

- **Source maps not uploaded.** The first init container uploads the
  exact frontend source maps for the selected release before migrations
  or the app can start. Check its logs with
  `kubectl -n wanderbound logs deploy/wanderbound-app -c sourcemaps`.
  Confirm that `wanderbound-sourcemaps-secrets` contains a valid
  `SENTRY_AUTH_TOKEN` and that `SENTRY_ORG` and `SENTRY_PROJECT` are set
  in `wanderbound-config`.
- **Database not ready.** The init container runs `alembic upgrade
  head` before the app starts. If the CNPG cluster is still
  bootstrapping, migrations fail. Check:
  `kubectl cnpg status -n wanderbound wanderbound-db`
- **Missing secrets.** The `wanderbound-secrets` Secret is
  SOPS-encrypted. If Flux can't decrypt it, the pod has no env vars.
  Check Flux SOPS status above.

---

## Image pull errors

```
kubectl -n <ns> describe pod <pod> | grep -A5 Events
```

The images are public, so `ghcr.io/itay-raveh/*` pull failures are
transient. Retry:

```
kubectl -n <ns> rollout restart deploy/<name>
```

If Flux image automation is writing bad digests, suspend it
(see "App rollback" in `disaster-recovery.md`).

---

## CNPG database issues

```
# Cluster health
kubectl cnpg status -n wanderbound wanderbound-db --verbose

# Postgres logs (structured JSON, filter with jq)
kubectl -n wanderbound logs wanderbound-db-1 | jq 'select(.logger=="postgres") | .record.message'

# Fatal errors only
kubectl -n wanderbound logs wanderbound-db-1 | jq -r '.record | select(.error_severity == "FATAL")'

# Backup status
kubectl -n wanderbound get backup -l cnpg.io/cluster=wanderbound-db
kubectl -n wanderbound wait --for=condition=LastBackupSucceeded cluster/wanderbound-db

# WAL archiving status
kubectl -n wanderbound wait --for=condition=ContinuousArchiving cluster/wanderbound-db
```

If the PG pod is stuck pending, check if the PVC is bound:

```
kubectl -n wanderbound get pvc
```

If the pod's storage is full, increase the PVC size in
`wanderbound-db.yaml`, commit, and push. CNPG handles the resize.

If the database is corrupted or unrecoverable, restore from backup
using the CNPG PITR procedure in `disaster-recovery.md`.

---

## etcd maintenance

The talos-backup CronJob snapshots etcd every 6 hours to S3. Use
these for day-2 etcd health.

```
# Status (DB size, leader, raft index)
talosctl etcd status

# Membership (should show exactly one member)
talosctl etcd members

# Check for alarms (NOSPACE = DB exceeded 2 GiB)
talosctl etcd alarm list

# If NOSPACE: disarm the alarm (talosctl has no defrag command;
# compaction happens automatically, or snapshot+restore to force it)
talosctl etcd alarm disarm
```

If etcd is unrecoverable, restore from a snapshot using the etcd
restore procedure in `disaster-recovery.md`.

---

## Cloudflare tunnel not connecting

The tunnel runs as a Helm-managed pod in the `cloudflared` namespace.

```
kubectl -n cloudflared get pods
kubectl -n cloudflared logs deploy/cloudflared-cloudflared --tail=100
```

If the pod is running but the site is unreachable, check the tunnel
status in the Cloudflare Zero Trust dashboard under Networks > Tunnels.

If the tunnel token is stale after a rebuild, `mise run rebuild`
regenerates and commits it. To refresh the token without a full
rebuild:

```
mise run tunnel:refresh
```
