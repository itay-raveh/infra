#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

cluster_key=bootstrap/cluster-age-key.sops.txt
secrets_file=tofu/secrets.sops.yaml

for f in .sops.yaml "$cluster_key" "$secrets_file"; do
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

step "moving age-plugin-yubikey identities to sops default location"
mkdir -p "$HOME/.config/sops/age"
mv "$HOME/.config/age-plugin-yubikey/identities.txt" "$HOME/.config/sops/age/keys.txt"
rmdir "$HOME/.config/age-plugin-yubikey" 2>/dev/null || true

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

  - path_regex: tofu/secrets\.sops\.yaml\$
    age: *yubis_only

  # The cluster software key cannot decrypt itself.
  - path_regex: bootstrap/cluster-age-key\.sops\.txt\$
    age: *yubis_only
EOF
mv .sops.yaml.tmp .sops.yaml

step "encrypting cluster key to $cluster_key"
printf '%s\n' "$CLUSTER_IDENTITY" | sops_encrypt_to "$cluster_key"
unset CLUSTER_IDENTITY

step "collecting secrets for $secrets_file"

# --- state encryption passphrase (generated) ---
STATE_PASSPHRASE=$(openssl rand -base64 48)
printf '    generated state passphrase\n' >&2

# --- tailscale auth key (interactive) ---
cat >&2 <<'INSTRUCTIONS'

    Tailscale auth key:
    1. Open https://login.tailscale.com/admin/settings/keys
    2. Click "Generate auth key"
    3. Settings:
       - Reusable:   ON  (survives cluster rebuilds)
       - Ephemeral:  ON  (auto-deregisters after destroy)
       - Tags:       ON, select tag:shire
       - Expiration: 90 days max (fine - the key lives in SOPS)
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

# --- external API tokens (interactive) ---
cat >&2 <<'INSTRUCTIONS'

    Paste each token when prompted (nothing echoes). Values come from:
    - Hetzner Cloud console  - project API token (Read & Write)
    - Hetzner Object Storage - S3 credential for the tfstate bucket
    - Cloudflare dashboard   - API token (Zone:DNS edit + Zero Trust edit)

INSTRUCTIONS

read -rs -p "    Hetzner Cloud API token: " HCLOUD_TOKEN; printf '\n' >&2
read -rs -p "    S3 access key ID: " S3_AK; printf '\n' >&2
read -rs -p "    S3 secret access key: " S3_SK; printf '\n' >&2
read -rs -p "    Cloudflare API token: " CF_TOKEN; printf '\n' >&2

step "encrypting secrets to $secrets_file"

# Build plaintext YAML, encrypt in one shot, then scrub variables.
cat > "$secrets_file.tmp" <<EOF
TF_VAR_encryption_passphrase: $STATE_PASSPHRASE
AWS_ACCESS_KEY_ID: $S3_AK
AWS_SECRET_ACCESS_KEY: $S3_SK
TF_VAR_hcloud_token: $HCLOUD_TOKEN
TF_VAR_cloudflare_api_token: $CF_TOKEN
TF_VAR_tailscale_auth_key: $TS_KEY
EOF
sops --encrypt --in-place "$secrets_file.tmp"
mv "$secrets_file.tmp" "$secrets_file"

unset STATE_PASSPHRASE TS_KEY HCLOUD_TOKEN S3_AK S3_SK CF_TOKEN

step "applying repository rulesets"
repo=itay-raveh/infra
gh api --method DELETE "repos/$repo/branches/main/protection" >/dev/null 2>&1 || true
for id in $(gh api "repos/$repo/rulesets" --jq '.[].id'); do
  gh api --method DELETE "repos/$repo/rulesets/$id" >/dev/null
done
for f in .github/rulesets/*.json; do
  gh api --method POST "repos/$repo/rulesets" --input "$f" >/dev/null
done

step "done. next: commit and push."
