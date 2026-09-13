#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/.."

cluster_key=bootstrap/cluster-age-key.sops.txt
secrets_dir=secrets

for f in .sops.yaml "$cluster_key" "$secrets_dir"; do
    if [[ -e "$f" ]]; then
        echo "error: $f already exists  - rotate via docs/secrets.md" >&2
        exit 1
    fi
done

step() { printf '\n==> %s\n' "$*" >&2; }

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
        --touch-policy always --pin-policy never \
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

  - path_regex: secrets/.*\.sops\.yaml\$
    age: *yubis_only

  # The cluster software key cannot decrypt itself.
  - path_regex: bootstrap/cluster-age-key\.sops\.txt\$
    age: *yubis_only
EOF
mv .sops.yaml.tmp .sops.yaml

step "encrypting cluster key to $cluster_key"
export CLUSTER_IDENTITY
bash scripts/encrypt-sops.sh "$cluster_key" binary -- \
    sh -c 'printf "%s\n" "$CLUSTER_IDENTITY"'
unset CLUSTER_IDENTITY

step "collecting secrets for $secrets_dir"

# --- state encryption passphrase (generated) ---
STATE_PASSPHRASE=$(openssl rand -base64 48)
printf '    generated state passphrase\n' >&2

# --- WireGuard management keys (generated) ---
WIREGUARD_SERVER_PRIVATE_KEY=$(wg genkey)
WIREGUARD_WORKSTATION_PRIVATE_KEY=$(wg genkey)
WIREGUARD_WORKSTATION_PUBLIC_KEY=$(printf '%s' "$WIREGUARD_WORKSTATION_PRIVATE_KEY" | wg pubkey)
printf '    generated WireGuard management keys\n' >&2

# --- external API tokens (interactive) ---
cat >&2 <<'INSTRUCTIONS'

    Paste each token when prompted (nothing echoes). Values come from:
    - Hetzner Cloud console  - project API token (Read & Write)
    - Hetzner Object Storage - S3 credential for the tfstate bucket
    - Cloudflare dashboard   - API token with these edit permissions:
      Zone (raveh.dev): DNS, Single Redirect, Workers Routes
      Account: Workers Scripts, Zero Trust
    - Tailscale admin console - OAuth client with these write scopes:
      policy_file, oauth_keys, feature_settings, dns, devices:core, auth_keys

INSTRUCTIONS

read -rs -p "    Hetzner Cloud API token: " HCLOUD_TOKEN; printf '\n' >&2
read -rs -p "    S3 access key ID: " S3_AK; printf '\n' >&2
read -rs -p "    S3 secret access key: " S3_SK; printf '\n' >&2
read -rs -p "    Cloudflare API token: " CF_TOKEN; printf '\n' >&2
read -rs -p "    Tailscale OAuth client ID: " TS_OAUTH_ID; printf '\n' >&2
read -rs -p "    Tailscale OAuth client secret: " TS_OAUTH_SECRET; printf '\n' >&2

step "encrypting secrets to $secrets_dir"
mkdir -p "$secrets_dir"
export STATE_PASSPHRASE S3_AK S3_SK HCLOUD_TOKEN CF_TOKEN TS_OAUTH_ID TS_OAUTH_SECRET
export WIREGUARD_SERVER_PRIVATE_KEY WIREGUARD_WORKSTATION_PUBLIC_KEY WIREGUARD_WORKSTATION_PRIVATE_KEY
bash scripts/encrypt-sops.sh "$secrets_dir/state.sops.yaml" json -- jq -n '{
    TF_VAR_encryption_passphrase: env.STATE_PASSPHRASE,
    AWS_ACCESS_KEY_ID: env.S3_AK, AWS_SECRET_ACCESS_KEY: env.S3_SK
}'
bash scripts/encrypt-sops.sh "$secrets_dir/tofu.sops.yaml" json -- jq -n '{
    TF_VAR_hcloud_token: env.HCLOUD_TOKEN, TF_VAR_cloudflare_api_token: env.CF_TOKEN,
    TF_VAR_s3_access_key_id: env.S3_AK, TF_VAR_s3_secret_access_key: env.S3_SK,
    TAILSCALE_OAUTH_CLIENT_ID: env.TS_OAUTH_ID, TAILSCALE_OAUTH_CLIENT_SECRET: env.TS_OAUTH_SECRET
}'
bash scripts/encrypt-sops.sh "$secrets_dir/wireguard.sops.yaml" json -- jq -n '{
    TF_VAR_wireguard_server_private_key: env.WIREGUARD_SERVER_PRIVATE_KEY,
    TF_VAR_wireguard_workstation_public_key: env.WIREGUARD_WORKSTATION_PUBLIC_KEY
}'
bash scripts/encrypt-sops.sh "$secrets_dir/workstation.sops.yaml" json -- jq -n '{
    WIREGUARD_WORKSTATION_PRIVATE_KEY: env.WIREGUARD_WORKSTATION_PRIVATE_KEY
}'

unset STATE_PASSPHRASE HCLOUD_TOKEN S3_AK S3_SK CF_TOKEN TS_OAUTH_ID TS_OAUTH_SECRET
unset WIREGUARD_SERVER_PRIVATE_KEY WIREGUARD_WORKSTATION_PRIVATE_KEY WIREGUARD_WORKSTATION_PUBLIC_KEY

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
