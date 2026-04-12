# Disaster recovery

The full-rebuild path is `setup.md` → "Every-rebuild path." DR is not
a separate procedure  - the every-rebuild path is written to double as
the DR path, because the only way to verify DR still works is to
exercise it regularly. Every time you rebuild shire for any reason,
you're drilling DR.

At v1 there is no stateful user data to restore. Every component -
Talos, Flux, cloudflared, Traefik, local-path-provisioner  - rebuilds
from git alone, and there are no PVCs bound to any user-facing app.
DR is literally "Every-rebuild path, end to end."

---

## Single points of failure

The every-rebuild path can recover from anything that lives in git or
in the cloud account. It cannot recover from losing the things below.

| SPOF | What you keep | If you lose it |
|---|---|---|
| **Tofu state bucket** (`raveh-infra-tfstate`) | Hetzner Object Storage versioning enabled. Quarterly `aws s3 sync` to a sibling bucket. | `tofu import` against live cloud resources can rebuild state, but it's a painful afternoon. Don't lose state. |
| **Both YubiKeys** | Primary on the keyring, backup in a physical safe offsite. Never travel with both. | Total cryptographic loss. Every encrypted file in the repo becomes permanent ciphertext. No recovery path. |
| **GitHub repo** | `git clone --mirror` to an offline drive monthly. Realistic threat is GitHub account suspension, not git corruption. | Repo is the source of truth. Without it, there is nothing to bootstrap from. |

The order of loss matters: losing the state bucket is a painful
afternoon; losing the repo is a painful week; losing both YubiKeys is
"start over from scratch with new cryptographic roots."

---

## Recovery scenarios

### Server is gone, everything else is fine

This is the most common case (Hetzner outage, you wanted a new instance
type, Talos upgrade). Run the every-rebuild path. The Hetzner Volume
has `prevent_destroy = true` so `tofu apply` re-attaches the existing
volume to the fresh node  - PVC data on `/var/mnt/data` survives.

Cluster downtime: ~5 minutes for the server replacement, plus a few
more for Flux first-reconcile.

### Server gone *and* volume gone

At v1 this is symmetric with the previous case because there's no PVC
data worth losing. Future phases that introduce real stateful data
will document their per-component recovery here (e.g. CNPG point-in-time
restore from a backup bucket).

### Tofu state bucket lost

1. Rebuild the bucket and the credential pair (one-time setup, step 1).
2. From a fresh checkout: re-init tofu against the new bucket
   (`tofu -chdir=tofu init -reconfigure`).
3. `tofu import` every resource you can find in the Hetzner +
   Cloudflare consoles. The set is small at v1: one server, one
   volume, one volume attachment, one ssh key, one snapshot, one
   tunnel, one tunnel config, two DNS records.
4. Once state matches reality, run the every-rebuild path normally.

### One YubiKey lost (primary or backup)

The other YubiKey can still decrypt everything. But you are now one
hardware failure from total loss  - initialize a replacement immediately.

1. Buy a new YubiKey.
2. `age-plugin-yubikey --generate --slot 1 --touch-policy cached --pin-policy once`
   on the new device.
3. Update `.sops.yaml` with the new public key alongside the surviving
   one. Keep the cluster software age key as a recipient where it
   already is.
4. For every committed `*.sops.*` file, re-encrypt it to add the new
   recipient: `sops updatekeys <file>`. YubiKey touch on the surviving
   key for each file.
5. Commit and push the re-encrypted files.
6. Store the new YubiKey wherever the lost one was (offsite if it was
   the backup, on the keyring if it was the primary).

### Both YubiKeys lost

There is no recovery path. The repo's encrypted material becomes
permanent ciphertext. Treat this as "start over":

1. Buy new YubiKeys and re-run `bootstrap/bootstrap.sh` from a clean
   working tree (delete the old `.sops.yaml`,
   `bootstrap/cluster-age-key.sops.txt`,
   `tofu/encryption-passphrase.sops.txt`, and
   `talos/tailscale-authkey.sops.txt` first so the preflight guard
   doesn't bail). The script regenerates the cluster software age
   key, state passphrase, and Tailscale auth key in one ceremony.
2. Generate a fresh Cloudflare tunnel token (destroy and recreate
   the tunnel via `tofu-apply`).
3. Destroy and recreate the tofu state (you cannot decrypt the old
   state without the old passphrase).
4. Run the every-rebuild path against the new cryptographic roots.

The cluster comes back. Any future stateful data that depended on the
old SOPS keys is unrecoverable.

### GitHub repo lost

1. Restore from the most recent `git clone --mirror` snapshot.
2. Push it to a new GitHub repo (or recreate the original).
3. Update `flux-bootstrap` task in `.mise.toml` if the repo coordinates
   changed.
4. Run the every-rebuild path normally.

If you have no mirror snapshot, the repo is gone for good  - every
encrypted artifact lived in git, and the cluster software age key,
state passphrase, and Tailscale auth key are unrecoverable. This is
the same outcome as losing both YubiKeys.

---

## DR drills

The cheapest drill is "rebuild for any reason." Talos minor upgrades,
server type changes, and curiosity all exercise the every-rebuild path
end-to-end. Don't engineer a separate DR test  - just be willing to
`tofu destroy` and rebuild whenever the change is small enough that
~5 minutes of downtime doesn't matter.

If a rebuild fails for a reason other than the change you intended,
**that's the bug to fix**  - not "skip the rebuild this time."
