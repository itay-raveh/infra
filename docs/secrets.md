# Secrets

[SOPS](https://github.com/getsops/sops) encrypts repository secrets. The
creation rules in [.sops.yaml](../.sops.yaml) select recipients by file path.

## Keys and access

| Encrypted content | Who can decrypt it |
|---|---|
| `tofu/secrets.sops.yaml` | Either YubiKey |
| `bootstrap/cluster-age-key.sops.txt` | Either YubiKey |
| `bootstrap/etcd-backup-age-key.sops.txt` | Either YubiKey |
| `clusters/**/*.sops.yaml` and `*.sops.json` | Either YubiKey or the Flux software age key |
| OpenTofu state and saved plans | The state-encryption passphrase in `tofu/secrets.sops.yaml` |
| Talos backup snapshots | The dedicated etcd backup key from `bootstrap/etcd-backup-age-key.sops.txt` |

The two hardware age keys are independent. The identity references on a
workstation tell the age plugin which hardware key to use; they do not contain
that private key. Each YubiKey also has a separate resident SSH key for signing.
See [workstation setup](setup.md#set-up-a-workstation) to restore access.

Flux stores its software age key in `flux-system/sops-age`. Access to that
Secret permits decryption of cluster manifests, including application
credentials. It does not decrypt the hardware-only files or OpenTofu state.

OpenTofu state contains generated Talos credentials and other sensitive
resource values. [backend.tf](../tofu/backend.tf) enforces AES-GCM encryption
for state and plans. The [wrapper](../scripts/tofu-wrapper.sh) decrypts provider
credentials and the passphrase into the command's environment. Local
kubeconfig, talosconfig and WireGuard configuration remain sensitive files
after a task exits.

## Edit a secret

Open an existing encrypted file through SOPS:

```bash
sops edit tofu/secrets.sops.yaml
```

SOPS opens plaintext in the configured editor and encrypts it on save.
Follow the hardware prompt. Review the diff before committing: cluster secret
values under `data` and `stringData` must remain encrypted, while resource
names and other metadata can remain readable.

## Create a cluster secret

Create the file at its final repository path so SOPS can select the matching
creation rule:

```bash
sops edit clusters/shire/apps/wanderbound/example.sops.yaml
```

In the editor, replace the template with the Secret manifest. Add the saved
file to the directory's `kustomization.yaml`.

When encrypting an existing plaintext manifest instead, explicitly supply the
destination name. Otherwise SOPS matches the input path against creation rules:

```bash
secret_path=clusters/shire/apps/wanderbound/example.sops.yaml
sops encrypt --filename-override "$secret_path" \
  --input-type yaml --output-type yaml /path/to/plaintext.yaml > "$secret_path"
```

Check that encryption succeeded before removing the plaintext source.
[The SOPS filename rules](https://sops.pages.dev/#using-sopsyaml-conf-to-select-kms-pgp-and-age-for-new-files)
explain this distinction. Run `mise run check` before committing. The
[sanity hook](../scripts/sops-sanity.sh) checks ciphertext markers and plaintext
Secret manifests; it does not prove that the intended recipients can decrypt.

## Replace a hardware key

Keep a working YubiKey available throughout the replacement.

1. Generate an age key and an SSH signing key on the replacement device using
   the [age plugin](https://github.com/str4d/age-plugin-yubikey#configuration)
   and the SSH key options in [bootstrap.sh](../bootstrap/bootstrap.sh).
   Use new local filenames so the working key is preserved.
2. Add the new age recipient to `.sops.yaml` and remove the retired recipient.
   Preserve the other hardware recipient and the Flux recipient where used.
3. Rewrap every encrypted file with `sops updatekeys <FILE>`. List the files with
   `git ls-files '*.sops.*'` and include both bootstrap keys.
4. Test decryption with the replacement device before retiring the working
   device. Register the new SSH public key as a GitHub signing key, test signing,
   and update the local Git configuration.
5. Review and commit the recipient changes. If the operator SSH public key
   changed, review an OpenTofu plan for the Hetzner rescue key as well.

`updatekeys` changes who can unwrap the existing data key. It does not revoke
access to old ciphertext in Git history. For a compromised key, rotate the
exposed credentials as well; recipient replacement alone is insufficient.
See [SOPS key management](https://sops.pages.dev/#key-rotation).

## Rotate the Flux key

Use an overlap period so Flux can read both old and new ciphertext:

1. Generate a replacement software key. Add its public recipient to the cluster
   creation rule alongside the old recipient, then rewrap cluster SOPS files.
2. Put both private identities in `flux-system/sops-age` and in the
   hardware-encrypted `bootstrap/cluster-age-key.sops.txt`. For the latter,
   use SOPS binary input/output and its final filename for rule selection.
3. Publish the rewrapped files and confirm that Flux reconciles them.
4. Remove the old recipient, rewrap and publish the cluster files again, then
   confirm decryption with the new identity alone.
5. Remove the retired identity from the live Secret and encrypted bootstrap
   file once the current revision no longer needs it.

Provider secrets and the dedicated etcd backup key keep their hardware-only
recipients. The [Flux SOPS guide](https://fluxcd.io/flux/guides/mozilla-sops/)
describes the decryption Secret format and multiple-key support.

## Rotate state or backup encryption keys

Changing `TF_VAR_encryption_passphrase` alone makes existing state unreadable.
Follow [OpenTofu's encryption migration procedure](https://opentofu.org/docs/language/state/encryption/):
configure the new method for writes and retain the old method as a read
fallback until state and required plans have been migrated. Keep the old
passphrase available for historical state versions that still use it.
This repository has no task that performs that migration.

For the etcd backup key, change the public recipient in
[talos-backup.yaml](../clusters/shire/infrastructure/controllers/talos-backup.yaml)
and keep the corresponding private key in the encrypted bootstrap file.
Retain earlier private keys for snapshots still encrypted to them. Check that
a new backup decrypts before retiring any key.
