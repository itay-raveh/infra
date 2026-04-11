# Secrets

How secrets are stored, encrypted, decrypted, and rotated in this repo.

## TL;DR

- Every secret in git is SOPS-encrypted to **three age recipients**:
  primary YubiKey, backup YubiKey, and the in-cluster software age key.
  A few high-sensitivity files use only the two YubiKeys (Flux never
  needs to read them).
- The repo is treated as if it were public. Encrypted files are
  AES-256-GCM with public-key recipients — safe to publish at any commit.
- The two YubiKeys are the hardware roots. Lose both and there is no
  recovery path.
- The cluster software age key (`bootstrap/cluster-age.key.sops`) is
  what Flux uses to decrypt manifests in-cluster, because a hardware
  YubiKey can't be present inside a pod.

## Threat model

**In scope:**

- **Repository leakage.** Anyone with a clone can read every encrypted
  file. Defense: SOPS payloads are designed to be public-safe.
- **Accidental plaintext commit.** Defense: pre-commit gitleaks (local,
  blocking) plus gitleaks in CI plus a `.sops.*` filename convention
  enforced by the sops-verify pre-commit hook.
- **Laptop compromise.** An attacker on the laptop cannot decrypt
  anything without a physical YubiKey touch. Plaintext lives in
  `$EDITOR` memory for seconds, never on disk.
- **Single YubiKey loss.** The other YubiKey can still decrypt
  everything. Rotate the lost key out of `.sops.yaml` and re-wrap.
- **Cluster compromise.** An attacker inside the cluster can read the
  `sops-age` Secret and decrypt everything. Defense: Talos immutability,
  no SSH on the node, Kubernetes API + Talos API closed to the public
  internet (Tailscale-only).

**Out of scope:**

- **Nation-state adversary.** We're defending against opportunistic
  attackers, not against someone who can coerce a YubiKey touch.
- **Both YubiKeys lost simultaneously.** Total cryptographic loss.
  Mitigation is "keep the backup offsite and don't lose both."
- **Tofu state bucket compromise.** Tofu state is itself client-side
  encrypted with AES-GCM and a passphrase that lives in SOPS, so the
  bucket leaking on its own is useless ciphertext.

## Trust roots

**Hardware:** two YubiKey 5s (primary + backup). Private keys live only
in PIV slot 1 on the device and cannot be extracted. Touch-cached
policy means one touch authorizes multiple decryptions within ~15s.
PIN-once policy means one PIN entry per boot.

**In-cluster helper:** one software age key, stored as
`bootstrap/cluster-age.key.sops` (encrypted to both YubiKeys).
Flux's kustomize-controller uses this key to decrypt `*.sops.yaml`
files during reconciliation. It's installed once per rebuild as a
Kubernetes Secret named `sops-age` in the `flux-system` namespace.

**Why three recipients (2 YubiKeys + 1 software), not two:**

- The 2 YubiKeys let the operator encrypt and decrypt files on the
  laptop with hardware backing and touch confirmation.
- The software key lets Flux decrypt files in-cluster.
- All three can decrypt everything, so losing any single one is
  recoverable.
- `bootstrap/cluster-age.key.sops` is the one exception: only the 2
  YubiKeys are recipients (the cluster key cannot decrypt itself).

## Where secrets live

| Secret | Path | Recipients | Notes |
|---|---|---|---|
| Cluster software age key | `bootstrap/cluster-age.key.sops` | YubiKeys only | Unwrapped into the `sops-age` Secret on every rebuild |
| Tofu state passphrase | `tofu/encryption-passphrase.sops.txt` | YubiKeys only | Flux never runs tofu, so it doesn't need to read this |
| Tailscale auth key | `talos/tailscale-authkey.sops.txt` | YubiKeys only | Decrypted at apply time, exported as `TF_VAR_tailscale_auth_key` |
| Cloudflare tunnel token | `clusters/frodo/infrastructure/controllers/cloudflared/tunnel-token.sops.yaml` | All three (Flux must read it) | Output of tofu, piped through SOPS by `mise run tofu-secrets-sync` |
| Talos PKI + bootstrap token + etcd encryption key | Inside tofu state | Protected by state encryption | Generated once by the `hcloud-talos` module on first apply |

`.env` itself is **never** committed. It contains the Hetzner API
token, the Object Storage credential, and the Cloudflare API token —
the bootstrap inputs the operator types in once per laptop. `.env` is
in `.gitignore`; the template `.env.example` is committed and contains
no secret values.

## Operator workflow

### Edit an existing encrypted file

```
sops clusters/frodo/infrastructure/controllers/<app>/admin.sops.yaml
```

YubiKey prompts for a touch, the file opens decrypted in `$EDITOR`,
saving re-encrypts to all configured recipients automatically. `git
diff` should show only the encrypted blob changing — if you see
plaintext-looking content, abort and investigate.

### Add a new encrypted file from scratch

```
# 1. Create the plaintext manifest
$EDITOR /tmp/secret.yaml

# 2. Encrypt in place into the right path
sops --encrypt /tmp/secret.yaml > clusters/frodo/.../secret.sops.yaml

# 3. Wipe the plaintext copy
shred -u /tmp/secret.yaml

# 4. Commit
git add clusters/frodo/.../secret.sops.yaml
```

The `.sops.yaml` `creation_rules:` section picks the recipient set
based on the file's path, so step 2 doesn't need a `--age` flag.

### Verify a file is actually encrypted

```
grep -q 'ENC\[' clusters/frodo/.../secret.sops.yaml && echo ok
```

The pre-commit `sops-verify` hook runs the same check on every commit
that touches a `.sops.*` file.

## YubiKey rotation

### Replacing a lost backup YubiKey

1. Buy a new YubiKey.
2. `age-plugin-yubikey --generate --slot 1 --touch-policy cached --pin-policy once`
   on the new device. Record the public key.
3. Edit `.sops.yaml`: replace the lost YubiKey's public key with the
   new one. Leave the surviving YubiKey and (where applicable) the
   cluster age key in place.
4. For every committed encrypted file, re-wrap to the new recipient
   set:

   ```
   sops updatekeys clusters/frodo/.../secret.sops.yaml
   sops updatekeys tofu/encryption-passphrase.sops.txt
   sops updatekeys talos/tailscale-authkey.sops.txt
   sops updatekeys bootstrap/cluster-age.key.sops
   # ...etc for every .sops.* file
   ```

   `updatekeys` re-wraps the data key without re-encrypting the
   payload, so the diff is small and reviewable.
5. Commit the updated `.sops.yaml` and the re-wrapped files in one PR.
   CI's gitleaks + sops-sanity jobs catch a botched `updatekeys` or a
   stray plaintext slip before merge.
6. Store the new YubiKey wherever the lost one was (offsite if it was
   the backup, on the keyring if it was the primary).

### Rotating the cluster software age key

This is a full one-time-setup replay because every encrypted file is
re-wrapped:

1. Generate a new key: `age-keygen -o /tmp/cluster.key`.
2. Encrypt it to YubiKeys only:
   `sops --encrypt --age <yubi1>,<yubi2> /tmp/cluster.key > bootstrap/cluster-age.key.sops`.
3. `shred -u /tmp/cluster.key`.
4. Update `.sops.yaml` with the new public key in place of the old one.
5. `sops updatekeys` every `clusters/**/*.sops.yaml` so Flux's new
   in-cluster key can decrypt them.
6. Commit, push.
7. On the running cluster, replace the `sops-age` Secret in
   `flux-system` with the unwrapped new key (same command as
   `setup.md` rebuild step 6).
8. `flux reconcile kustomization infrastructure` to confirm Flux can
   still decrypt everything.

The state passphrase, Tailscale auth key, and cluster age key file
itself don't need re-wrapping in this case (they were never recipients
of the cluster age key — only the YubiKeys were).

### Rotating the state passphrase

1. Generate a new passphrase: `openssl rand -base64 48 > /tmp/pass`.
2. Run `tofu init -backend-config=...` interactively with the **old**
   passphrase still active, then `tofu apply` once to confirm state
   reads OK.
3. Add the new passphrase to the encryption block as a fallback method
   (OpenTofu supports a method rotation array). Apply once.
4. Promote the new passphrase to primary, demote the old. Apply once.
5. Drop the old method. Apply once.
6. Encrypt the new passphrase as
   `tofu/encryption-passphrase.sops.txt` and commit.
7. `shred -u /tmp/pass`.

This is the only rotation that touches tofu state directly, so it's
worth doing during a maintenance window.

## CI enforcement

Every push and PR runs:

- `gitleaks` — catches accidental plaintext credentials in the diff
- `sops-sanity` — every `*.sops.*` file actually contains `ENC[`
  markers, and no plaintext `kind: Secret` lives under `clusters/`
- `flux-build` — `flux build kustomization` dry-run, which would fail
  if a referenced Secret is missing or malformed
- `tofu-validate` — `tofu fmt -check` + `tofu validate`

All four are required green for a merge to `main`.
