# Troubleshooting

## A site is unavailable

For Worker-hosted sites, check the application's deployment and
[Cloudflare settings](cloudflare.md). For Tunnel-hosted sites:

```bash
kubectl get nodes
flux get kustomizations -A
kubectl get pods -A
kubectl -n cloudflared logs deploy/cloudflared-cloudflared --tail=100
kubectl -n traefik logs deploy/traefik --tail=100
```

- Kubernetes connection failure: [management access](#management-apis-are-unreachable).
- Tunnel authentication error: [refresh the token](#cloudflare-tunnel-authentication-fails).
- Application restarts: [previous container logs](#a-container-restarts-or-cannot-pull-its-image).

`mise run unhealthy` filters by pod phase and can miss `CrashLoopBackOff`.
Use `kubectl get pods -A` to include those pods.

## Management APIs are unreachable

```bash
sudo wg show shire
ping -c 3 10.200.0.1
talosctl version
```

With no recent handshake, check the endpoint, UDP 51820 rule and peer keys.
`mise run wireguard:configure` restores the workstation peer.
[WireGuard recovery](disaster-recovery.md#recover-wireguard-access) repairs the node side.

If Talos responds but physical networking is wrong, compare `talosctl get links`
and `talosctl get cmdline` with [main.tf](../tofu/main.tf). The module expects
`eth0` and `eth1`; the installer sets `net.ifnames=0`.

## Flux is not reconciling

```bash
mise run flux:unhealthy
flux get sources git -A
flux get sources helm -A
flux get sources oci -A
flux get helmreleases -A
```

After fixing a failed Helm upgrade, reset its retry counter:

```bash
flux reconcile helmrelease wanderbound -n wanderbound --with-source --reset
```

For other releases, use the namespace from `flux get helmreleases -A`.

### SOPS decryption fails

Compare the failing file's recipients with [.sops.yaml](../.sops.yaml).
To replace a missing or stale `flux-system/sops-age` Secret:

```bash
set -o pipefail
sops decrypt bootstrap/cluster-age-key.sops.txt \
  | kubectl create secret generic sops-age \
      -n flux-system --from-file=age.agekey=/dev/stdin \
      --dry-run=client -o yaml \
  | kubectl apply -f -
mise run reconcile
```

For a file with the wrong recipients, run `sops updatekeys '<FILE>'` and commit it.

## A container restarts or cannot pull its image

```bash
kubectl -n '<NAMESPACE>' describe pod '<POD>'
kubectl -n '<NAMESPACE>' logs '<POD>' --previous
```

`describe` shows exit reasons and image-pull errors in the pod events.
`--previous` reads the last terminated container's logs.
For a bad chart update, use [release rollback](disaster-recovery.md#roll-back-an-application-release).

## PostgreSQL is unhealthy

```bash
kubectl cnpg status -n wanderbound wanderbound-db --verbose
kubectl -n wanderbound get pvc
kubectl -n wanderbound get backups -l cnpg.io/cluster=wanderbound-db
kubectl -n wanderbound describe cluster wanderbound-db
```

For a pending pod, inspect its PVC events. For PostgreSQL errors:

```bash
kubectl -n wanderbound logs '<POSTGRES_POD>' \
  | jq -r 'select(.logger == "postgres") | .record.message'
```

Backup failures appear in `ContinuousArchiving` and `LastBackupSucceeded`,
even when the database is ready. See [database recovery](disaster-recovery.md#restore-postgresql).

## etcd reports an alarm

```bash
talosctl etcd status
talosctl etcd members
talosctl etcd alarm list
```

For `NOSPACE`, compare `DB SIZE` with `IN USE`.
[Talos maintenance](https://docs.siderolabs.com/talos/v1.12/build-and-extend-talos/cluster-operations-and-maintenance/etcd-maintenance)
covers quotas and defragmentation. `talosctl etcd defrag` blocks reads and
writes on the member; `shire` has only one. Clear the alarm after the database
is below quota.

## Cloudflare Tunnel authentication fails

If the connector has a stale token after a rebuild:

```bash
mise run tunnel:refresh
```

The refresh reads the token from OpenTofu state and writes an encrypted
manifest. Commit and merge it, then run `mise run reconcile`.

## OpenTofu version mismatch

Compare `mise exec -- tofu version` with the pins in
[mise.toml](../mise.toml) and [versions.tf](../tofu/versions.tf).
Resolve differing pins before retrying the OpenTofu command.
