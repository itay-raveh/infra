# Troubleshooting

## The workstation cannot access the YubiKey

```bash
systemctl status pcscd.socket pcscd.service
journalctl -u pcscd.service -n 50 --no-pager
ykman piv info
age-plugin-yubikey --list
```

| Failure | Check |
|---|---|
| `LIBUSB_ERROR_BUSY` or `Open Port` | Competing `pcscd` processes, including older Authenticator Snaps ([upstream issue](https://github.com/Yubico/yubioath-flutter/issues/766)) |
| `Failed to decrypt YubiKey stanza` | Recipient, [identity reference](setup.md#age-identity), and touch when the key flashes |
| Signing refused | Connected signing key and agent; do not bypass signing |

## Management APIs are unreachable

```bash
sudo wg show shire
ping -c 3 10.200.0.1
talosctl version
```

No handshake: check endpoint, UDP 51820 and peer keys. `mise run wireguard:configure` repairs the workstation peer; [recovery](disaster-recovery.md#recover-wireguard-access) covers the node side.

If Talos responds but networking is wrong, compare `talosctl get links` and `talosctl get cmdline` with [main.tf](../tofu/main.tf). The module expects `eth0` and `eth1`, using `net.ifnames=0`.

## A site is unavailable

```bash
mise run unhealthy
kubectl -n cloudflared logs deploy/cloudflared-cloudflared --tail=100
kubectl -n traefik logs deploy/traefik --tail=100
kubectl -n '<NAMESPACE>' describe pod '<POD>'
kubectl -n '<NAMESPACE>' logs '<POD>' --previous
```

Worker-hosted sites use the application's Worker logs. For Tunnel authentication failures, regenerate its Secret with `mise run tunnel:refresh` and submit the encrypted change. Pod events show failed image pulls and scheduling; previous logs show crashes.

## Flux is not reconciling

```bash
mise run flux:unhealthy
flux get sources all -A
flux get helmreleases -A
```

After fixing a failed Helm upgrade:

```bash
flux reconcile helmrelease '<RELEASE>' -n '<NAMESPACE>' --with-source --reset
```

Pause and resume a Kustomization with `flux suspend kustomization '<NAME>'` and `flux resume kustomization '<NAME>'`.

### SOPS decryption fails

Check file recipients against [.sops.yaml](../.sops.yaml). Restore the Flux key if missing or stale:

```bash
set -o pipefail
sops decrypt bootstrap/cluster-age-key.sops.txt | kubectl create secret generic sops-age -n flux-system \
  --from-file=age.agekey=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -
mise run reconcile
```

For wrong file recipients, run `sops updatekeys '<FILE>'` and submit the change. If a live Secret contains `ENC[...]`, check that Kustomize preserved its SOPS metadata; see [Secret format](secrets.md#create-a-cluster-secret).

## PostgreSQL is unhealthy

```bash
kubectl cnpg status -n '<NAMESPACE>' '<CLUSTER>' --verbose
kubectl -n '<NAMESPACE>' get pvc,backups,certificates
kubectl -n '<NAMESPACE>' describe cluster '<CLUSTER>'
kubectl -n '<NAMESPACE>' logs '<POSTGRES_POD>' -c postgres
```

| Symptom | Check |
|---|---|
| Pending pod | PVC and scheduling events |
| Missing TLS Secret | Certificate, Issuer and ACME Challenge status |
| Backup failure | `ContinuousArchiving` and `LastBackupSucceeded` conditions; [recovery](disaster-recovery.md#restore-postgresql) |
| Full volume | Storage class before changing `spec.storage.size`; local-path uses the node disk, not a resizable Hetzner Volume |

## etcd reports an alarm

```bash
talosctl etcd status
talosctl etcd members
talosctl etcd alarm list
```

For `NOSPACE`, compare `DB SIZE` with `IN USE` and follow [Talos maintenance](https://docs.siderolabs.com/talos/v1.14/build-and-extend-talos/cluster-operations-and-maintenance/etcd-maintenance). Defragmentation blocks reads and writes on the single member. Clear the alarm after usage falls below quota.

## OpenTofu version mismatch

Compare `mise exec -- tofu version` with [mise.toml](../mise.toml) and [versions.tofu](../tofu/versions.tofu). Run `mise install opentofu`; check shell activation if another executable still wins.
