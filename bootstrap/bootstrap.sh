#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

cluster_key=bootstrap/cluster-age-key.sops.txt
state_passphrase=tofu/encryption-passphrase.sops.txt
tailscale_authkey=talos/tailscale-authkey.sops.txt

for f in .sops.yaml "$cluster_key" "$state_passphrase" "$tailscale_authkey"; do
    if [[ -e "$f" ]]; then
        echo "error: $f already exists  - rotate via docs/secrets.md" >&2
        exit 1
    fi
done

step() { printf '\n==> %s\n' "$*" >&2; }

# Write stdin atomically to $1, encrypted via sops with the rules in
# .sops.yaml. Temp-then-rename so a failure leaves no partial artifact
# that the preflight guard would trip on next run.
sops_encrypt_to() {
    local dest=$1
    sops --encrypt --input-type binary --filename-override "$dest" /dev/stdin \
        > "$dest.tmp"
    mv "$dest.tmp" "$dest"
}

gh auth status >/dev/null

gen_yubikey() {
    local label="$1"
    local ssh_file="$HOME/.ssh/id_ed25519_sk"
    [[ "$label" == backup ]] && ssh_file="${ssh_file}_backup"

    step "plug in the $label YubiKey (unplug any other)"
    read -r -p "    press Enter when ready... " _ >&2

    if [[ -e "$ssh_file" ]]; then
        echo "error: $ssh_file already exists; refusing to overwrite" >&2
        exit 1
    fi

    local age_pub
    age_pub=$(age-plugin-yubikey --generate --slot 1 \
        --touch-policy cached --pin-policy once \
        | grep -m1 -oE 'age1yubikey1[02-9ac-hj-np-z]+')
    if [[ -z "$age_pub" ]]; then
        echo "error: could not parse age pubkey from age-plugin-yubikey" >&2
        exit 1
    fi
    printf '    age pubkey: %s\n' "$age_pub" >&2

    ssh-keygen -t ed25519-sk -O resident -O "application=ssh:yubikey-$label" \
        -f "$ssh_file" -C "yubikey-$label" >&2

    printf '%s' "$age_pub"
}

PRIMARY_AGE=$(gen_yubikey primary)
BACKUP_AGE=$(gen_yubikey backup)

step "generating cluster software age key (in memory)"
CLUSTER_IDENTITY=$(age-keygen 2>/dev/null)
CLUSTER_AGE=$(printf '%s\n' "$CLUSTER_IDENTITY" | awk '/^# public key:/ {print $NF}')
if [[ -z "$CLUSTER_AGE" ]]; then
    echo "error: could not parse cluster pubkey from age-keygen output" >&2
    exit 1
fi
printf '    cluster pubkey: %s\n' "$CLUSTER_AGE" >&2

# Do the fallible network/config steps before writing any persistent
# files, so a failure here leaves no half-committed state behind.
gh ssh-key add "$HOME/.ssh/id_ed25519_sk.pub"        --type signing --title "yubikey-primary"
gh ssh-key add "$HOME/.ssh/id_ed25519_sk_backup.pub" --type signing --title "yubikey-backup"

git config --global gpg.format ssh
git config --global user.signingkey "$HOME/.ssh/id_ed25519_sk.pub"
git config --global commit.gpgsign true

step "writing .sops.yaml"
cat > .sops.yaml.tmp <<EOF
x-yubis-only: &yubis_only >-
  $PRIMARY_AGE,
  $BACKUP_AGE

creation_rules:
  - path_regex: clusters/.*\.sops\.(yaml|json)\$
    encrypted_regex: '^(data|stringData)\$'
    age: >-
      $PRIMARY_AGE,
      $BACKUP_AGE,
      $CLUSTER_AGE

  - path_regex: talos/tailscale-authkey\.sops\.txt\$
    age: *yubis_only

  - path_regex: tofu/encryption-passphrase\.sops\.txt\$
    age: *yubis_only

  # The cluster software key cannot decrypt itself.
  - path_regex: bootstrap/cluster-age-key\.sops\.txt\$
    age: *yubis_only
EOF
mv .sops.yaml.tmp .sops.yaml

step "encrypting cluster key to $cluster_key"
printf '%s\n' "$CLUSTER_IDENTITY" | sops_encrypt_to "$cluster_key"
unset CLUSTER_IDENTITY

step "generating tofu state passphrase -> $state_passphrase"
openssl rand -base64 48 | sops_encrypt_to "$state_passphrase"

step "tailscale auth key"
cat >&2 <<'INSTRUCTIONS'

    1. Open https://login.tailscale.com/admin/settings/keys
    2. Click "Generate auth key"
    3. Settings:
       - Reusable:   ON  (survives cluster rebuilds)
       - Ephemeral:  OFF
       - Tags:       ON, select tag:shire
       - Expiration: 90 days max (fine  - the key lives in SOPS)
       - If your tailnet has Device Approval enabled, also turn
         Pre-approved ON; otherwise the toggle won't appear.
    4. Click Generate, copy the tskey-auth-... value
    5. Paste below (nothing echoes; press Enter when done)

INSTRUCTIONS

read -rs -p "    tailscale auth key: " TS_KEY
printf '\n' >&2

if [[ ! "$TS_KEY" =~ ^tskey-auth- ]]; then
    echo "error: expected key to start with 'tskey-auth-'" >&2
    exit 1
fi

printf '%s' "$TS_KEY" | sops_encrypt_to "$tailscale_authkey"
unset TS_KEY
printf '    encrypted to %s\n' "$tailscale_authkey" >&2

step "applying repository rulesets"
repo=itay-raveh/infra
gh api --method DELETE "repos/$repo/branches/main/protection" >/dev/null 2>&1 || true
for id in $(gh api "repos/$repo/rulesets" --jq '.[].id'); do
  gh api --method DELETE "repos/$repo/rulesets/$id" >/dev/null
done
gh api --method POST "repos/$repo/rulesets" --input .github/rulesets/main-branch.json >/dev/null
gh api --method POST "repos/$repo/rulesets" --input .github/rulesets/tags.json >/dev/null

step "done. next: commit and push."
