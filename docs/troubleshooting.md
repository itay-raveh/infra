# Troubleshooting

Run commands from the repository root with the tools and client configuration
from [workstation setup](setup.md#set-up-a-workstation).

## A site is unavailable

First identify where the request fails. A Worker-hosted site does not pass
through the Kubernetes cluster; check its application deployment and the
Cloudflare dashboard.

For a site served through the Tunnel, inspect the cluster and ingress:

```bash
kubectl get nodes
flux get kustomizations -A
kubectl get pods -A
kubectl -n cloudflared logs deploy/cloudflared-cloudflared --tail=100
kubectl -n traefik logs deploy/traefik --tail=100
```

If `kubectl` cannot connect, check [management access](#management-apis-are-unreachable).
If the Tunnel logs show authentication failures, see
[Tunnel credentials](#cloudflare-tunnel-authentication-fails). Otherwise inspect
the application's pod status and logs. `mise run unhealthy` omits pods whose
phase is `Running`, which can include containers in `CrashLoopBackOff`; use the
full pod list above when diagnosing restarts.

## Management APIs are unreachable

Check the workstation tunnel and the Talos endpoint:

```bash
sudo wg show shire
ping -c 3 10.200.0.1
talosctl version
```

No recent handshake points to the endpoint, UDP 51820 connectivity or peer
configuration. Restore the workstation configuration with
`mise run wireguard:configure`. If the server's WireGuard configuration is
missing, use [WireGuard recovery](disaster-recovery.md#recover-wireguard-access).

A handshake without API access needs further checks of routing, firewall and
node health. If Talos is reachable, inspect `talosctl get links` and
`talosctl get cmdline`. The installer configuration in
[tofu/main.tf](../tofu/main.tf) sets `net.ifnames=0`, and the module expects
physical links named `eth0` and `eth1`. Compare a differing live configuration
with the desired machine configuration before applying a repair.

## Flux is not reconciling

Find the failing resource and source:

```bash
mise run flux:unhealthy
flux get sources git -A
flux get sources helm -A
flux get sources oci -A
flux get helmreleases -A
```

Read the reported condition before retrying. After fixing the source or
manifest, run `mise run reconcile`. For an exhausted Wanderbound Helm upgrade,
reset its retry count and reconcile its source:

```bash
flux reconcile helmrelease wanderbound -n wanderbound --with-source --reset
```

Use the namespace reported by `flux get helmreleases -A` for other releases.
See [Flux Helm reconciliation](https://fluxcd.io/flux/cmd/flux_reconcile_helmrelease/)
for the reset behavior.

### SOPS decryption fails

Check the error for the encrypted filename and recipient. If
`flux-system/sops-age` is missing or contains the wrong key, reseed it from
the encrypted bootstrap file:

```bash
set -o pipefail
sops decrypt bootstrap/cluster-age-key.sops.txt \
  | kubectl create secret generic sops-age \
      -n flux-system --from-file=age.agekey=/dev/stdin \
      --dry-run=client -o yaml \
  | kubectl apply -f -
mise run reconcile
```

If decryption still fails, compare the file's recipients with
[.sops.yaml](../.sops.yaml). Reseeding a key cannot repair a file encrypted to
the wrong recipient. See [secret creation](secrets.md#create-a-cluster-secret).

## A container restarts or cannot pull its image

Substitute the namespace and pod from `kubectl get pods -A`:

```bash
kubectl -n '<NAMESPACE>' describe pod '<POD>'
kubectl -n '<NAMESPACE>' logs '<POD>' --previous
```

For restarts, inspect the exit reason and previous container logs. For pull
failures, read the pod events for the image name, registry response and
credential errors. Correct the manifest or credentials in Git before
reconciling. If an automated chart update caused the failure, use
[application rollback](disaster-recovery.md#roll-back-an-application-release).

## PostgreSQL is unhealthy

Inspect the cluster, storage and backup conditions:

```bash
kubectl cnpg status -n wanderbound wanderbound-db --verbose
kubectl -n wanderbound get pvc
kubectl -n wanderbound get backups -l cnpg.io/cluster=wanderbound-db
kubectl -n wanderbound describe cluster wanderbound-db
```

A pending database pod may be waiting for its PVC. Check the PVC events and
storage provisioner before changing the database. For database errors, read
the affected pod's logs:

```bash
kubectl -n wanderbound logs '<POSTGRES_POD>' \
  | jq -r 'select(.logger == "postgres") | .record.message'
```

Inspect `ContinuousArchiving` and `LastBackupSucceeded` conditions separately
from database readiness. A healthy database can still have failing backups.
Use [PostgreSQL recovery](disaster-recovery.md#restore-postgresql) if the data
needs restoration.

## etcd reports an alarm

Inspect the database and membership:

```bash
talosctl etcd status
talosctl etcd members
talosctl etcd alarm list
```

The current configuration has one control-plane member. A `NOSPACE` alarm
means the backend quota has been reached. Compare database size with space
in use and follow [Talos etcd maintenance](https://docs.siderolabs.com/talos/v1.12/build-and-extend-talos/cluster-operations-and-maintenance/etcd-maintenance)
to address the cause. `talosctl etcd defrag` is available, but blocks reads
and writes on the member while it runs. On this cluster that interrupts the
only etcd member.

Disarm an alarm only after resolving its cause, then recheck status. For an
unrecoverable database, use [etcd recovery](disaster-recovery.md#restore-etcd).

## Cloudflare Tunnel authentication fails

Check the connector logs and its status in the Cloudflare Tunnel dashboard:

```bash
kubectl -n cloudflared get pods
kubectl -n cloudflared logs deploy/cloudflared-cloudflared --tail=100
```

If the token no longer matches the OpenTofu-managed tunnel, regenerate it:

```bash
mise run tunnel:refresh
```

Review and merge the encrypted manifest change, then reconcile Flux.
The refresh task only changes the working tree; it does not update the running
connector by itself. See [credential refresh](deploying.md#refresh-generated-credentials).

## OpenTofu version mismatch

Compare `mise exec -- tofu version`, the `opentofu` pin in
[mise.toml](../mise.toml), and `required_version` in
[tofu/versions.tf](../tofu/versions.tf). The installed CLI must satisfy the
configuration constraint. Resolve inconsistent pins before running `doctor`,
OpenTofu validation or a rebuild; removing the constraint does not establish
compatibility.
