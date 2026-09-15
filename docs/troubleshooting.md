# Troubleshooting

## The workstation cannot access the YubiKey

On Linux, the [age plugin requires `pcscd`](https://github.com/str4d/age-plugin-yubikey#linux-bsd-etc).
Check the service and PIV access:

```bash
systemctl status pcscd.socket pcscd.service
journalctl -u pcscd.service -n 50 --no-pager
ykman piv info
```

`LIBUSB_ERROR_BUSY` or `RFInitializeReader() Open Port` can indicate competing
`pcscd` processes, including one bundled with older Yubico Authenticator Snaps
([issue #766](https://github.com/Yubico/yubioath-flutter/issues/766)).
Stop the competing service, reconnect the key and retry `ykman piv info`.

If PIV works but SOPS reports `Failed to decrypt YubiKey stanza`, compare
`age-plugin-yubikey --list` with the encrypted file's recipients and check the
[registered identity](setup.md#age-identity). Touch the key when it flashes.
With an `always` touch policy, each file requires a touch; `tofu plan` decrypts
three files. [Plugin touch-failure report](https://github.com/str4d/age-plugin-yubikey/issues/150).

## A site is unavailable

For Worker-hosted sites, check the application's deployment and
[Cloudflare settings](cloudflare.md). For Tunnel-hosted sites:

```bash
kubectl get nodes
flux get kustomizations -A
mise run unhealthy
kubectl -n cloudflared logs deploy/cloudflared-cloudflared --tail=100
kubectl -n traefik logs deploy/traefik --tail=100
```

- Kubernetes connection failure: [management access](#management-apis-are-unreachable).
- Tunnel authentication error: [refresh the token](#cloudflare-tunnel-authentication-fails).
- Application restarts: [previous container logs](#a-container-restarts-or-cannot-pull-its-image).

`unhealthy` includes running pods whose readiness condition is false or missing,
including `CrashLoopBackOff`.

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
flux get sources all -A
flux get helmreleases -A
```

After fixing a failed Helm upgrade, reset its retry counter:

```bash
flux reconcile helmrelease wanderbound -n wanderbound --with-source --reset
```

For other releases, use the namespace from `flux get helmreleases -A`.

To pause reconciliation while investigating a resource:

```bash
flux suspend kustomization infrastructure -n flux-system
```

After correcting the manifest, resume and reconcile it:

```bash
flux resume kustomization infrastructure -n flux-system
mise run reconcile
```

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

`describe` shows exit reasons and image-pull errors; `--previous` reads the last
terminated container's logs. For pull failures, check image names, tags and
registry credentials. After fixing the cause, retry:

```bash
kubectl -n '<NAMESPACE>' rollout restart deploy/'<DEPLOYMENT>'
```

For a bad chart, inspect its policy before [rolling back](disaster-recovery.md#roll-back-an-application-release):

```bash
flux get image policy -A
```

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

To wait for those conditions:

```bash
kubectl -n wanderbound wait --for=condition=LastBackupSucceeded cluster/wanderbound-db --timeout=5m
kubectl -n wanderbound wait --for=condition=ContinuousArchiving cluster/wanderbound-db --timeout=5m
```

For a full volume, check its storage class before increasing `spec.storage.size`
in [wanderbound-db.yaml](../clusters/shire/apps/wanderbound/wanderbound-db.yaml).
The default local-path storage uses the node's disk; it does not provision a
larger Hetzner Volume when the PVC size changes.

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

Commit and merge the encrypted manifest, then run `mise run reconcile`.

## OpenTofu version mismatch

Compare `mise exec -- tofu version` with the pins in
[mise.toml](../mise.toml) and [versions.tofu](../tofu/versions.tofu).
Run `mise install opentofu` to install the pinned version. If the shell still
selects another executable, use `mise exec -- tofu version` and check mise's
shell activation.
