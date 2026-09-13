#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/.."

cluster_key=bootstrap/cluster-age-key.sops.txt
etcd_key=bootstrap/etcd-backup-age-key.sops.txt
flux_secret=clusters/shire/flux-system/flux-github-app.sops.yaml
secrets_dir=secrets
ssh_key_dir=${BOOTSTRAP_SSH_KEY_DIR:-$HOME/.ssh}
identity_file=${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}

for f in .sops.yaml "$cluster_key" "$etcd_key" "$flux_secret" "$secrets_dir" \
    "$ssh_key_dir/id_ed25519_sk" "$ssh_key_dir/id_ed25519_sk.pub" \
    "$ssh_key_dir/id_ed25519_sk_backup" "$ssh_key_dir/id_ed25519_sk_backup.pub"; do
    if [[ -e "$f" ]]; then
        echo "error: $f already exists; use docs/secrets.md for rotation" >&2
        exit 1
    fi
done

step() { printf '\n==> %s\n' "$*" >&2; }

for command in gh git age-plugin-yubikey age-keygen ssh-keygen sops jq openssl wg yq; do
    command -v "$command" >/dev/null || { echo "error: missing command: $command" >&2; exit 1; }
done
gh auth status >/dev/null
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

read_required() {
    local variable=$1 prompt=$2
    if ! read -rs -p "    $prompt: " "${variable?}"; then
        printf '\nerror: no value supplied for %s\n' "$prompt" >&2
        exit 1
    fi
    printf '\n' >&2
    if [[ -z ${!variable} ]]; then
        printf 'error: %s cannot be empty\n' "$prompt" >&2
        exit 1
    fi
    export "${variable?}"
}

step "collecting credentials (input is hidden)"
read_required HCLOUD_TOKEN "Hetzner Cloud API token"
read_required S3_AK "S3 access key ID"
read_required S3_SK "S3 secret access key"
read_required CF_TOKEN "Cloudflare zone and services API token"
read_required CF_ACCOUNT_TOKEN "Cloudflare account and analytics API token"
read_required CF_PRIMARY_EMAIL "Cloudflare daily login email"
read_required CF_GMAIL_EMAIL "Cloudflare Gmail recovery login"
read_required CF_PROTON_EMAIL "Cloudflare native Proton recovery login"
read_required TS_OAUTH_ID "Tailscale OAuth client ID"
read_required TS_OAUTH_SECRET "Tailscale OAuth client secret"
read_required UPLOAD_PROJECT_ID "Wanderbound upload credential project ID"
read_required UPLOAD_ACCESS_KEY_ID "Wanderbound upload access key ID"
read_required SENTRY_AUTH_TOKEN "Sentry API token"
read_required FLUX_APP_ID "Flux GitHub App ID"
read_required FLUX_APP_INSTALLATION_ID "Flux GitHub App installation ID"
read_required FLUX_APP_PRIVATE_KEY_FILE "Flux GitHub App private-key PEM path"
openssl pkey -in "$FLUX_APP_PRIVATE_KEY_FILE" -noout
FLUX_APP_PRIVATE_KEY=$(cat "$FLUX_APP_PRIVATE_KEY_FILE")
export FLUX_APP_PRIVATE_KEY

mkdir -p "$ssh_key_dir" "$(dirname "$identity_file")"
touch "$identity_file"
chmod 600 "$identity_file"

gen_yubikey() {
    local label="$1"
    local ssh_file="$ssh_key_dir/id_ed25519_sk"
    [[ "$label" == backup ]] && ssh_file="${ssh_file}_backup"

    step "plug in the $label YubiKey (unplug any other)"
    read -r -p "    press Enter when ready... " _ >&2 || return

    if [[ -e "$ssh_file" ]]; then
        echo "error: $ssh_file already exists; refusing to overwrite" >&2
        exit 1
    fi

    local identity age_pub
    identity=$(age-plugin-yubikey --generate --slot 1 \
        --touch-policy always --pin-policy never) || return
    printf '%s\n' "$identity" >> "$identity_file" || return
    age_pub=$(age-plugin-yubikey --list --slot 1 | awk '/^age1/ {print; exit}') || return
    if [[ -z "$age_pub" ]]; then
        echo "error: could not parse age pubkey from age-plugin-yubikey" >&2
        exit 1
    fi
    printf '    age pubkey: %s\n' "$age_pub" >&2

    ssh-keygen -t ed25519-sk -O resident -O "application=ssh:yubikey-$label" \
        -f "$ssh_file" -C "yubikey-$label" >&2 || return

    printf '%s' "$age_pub"
}

PRIMARY_AGE=$(gen_yubikey primary)
BACKUP_AGE=$(gen_yubikey backup)

step "generating Flux and etcd backup keys"
CLUSTER_IDENTITY=$(age-keygen 2>/dev/null)
CLUSTER_AGE=$(printf '%s\n' "$CLUSTER_IDENTITY" | age-keygen -y)
ETCD_IDENTITY=$(age-keygen 2>/dev/null)
ETCD_AGE=$(printf '%s\n' "$ETCD_IDENTITY" | age-keygen -y)
printf '    cluster pubkey: %s\n' "$CLUSTER_AGE" >&2

gh ssh-key add "$ssh_key_dir/id_ed25519_sk.pub"        --type signing --title "yubikey-primary"
gh ssh-key add "$ssh_key_dir/id_ed25519_sk_backup.pub" --type signing --title "yubikey-backup"

git config --global gpg.format ssh
git config --global user.signingkey "$ssh_key_dir/id_ed25519_sk.pub"
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

  - path_regex: bootstrap/.*\.sops\.txt\$
    age: *yubis_only
EOF
mv .sops.yaml.tmp .sops.yaml

step "encrypting cluster key to $cluster_key"
export CLUSTER_IDENTITY
bash scripts/encrypt-sops.sh "$cluster_key" binary -- \
    sh -c 'printf "%s\n" "$CLUSTER_IDENTITY"'
unset CLUSTER_IDENTITY

step "encrypting etcd backup key to $etcd_key"
export ETCD_IDENTITY
bash scripts/encrypt-sops.sh "$etcd_key" binary -- \
    sh -c 'printf "%s\n" "$ETCD_IDENTITY"'
unset ETCD_IDENTITY
export ETCD_AGE
yq -i '(select(.kind == "CronJob" and .metadata.name == "talos-backup") |
    .spec.jobTemplate.spec.template.spec.containers[].env[] |
    select(.name == "AGE_X25519_PUBLIC_KEY").value) = strenv(ETCD_AGE)' \
    clusters/shire/infrastructure/controllers/talos-backup.yaml
unset ETCD_AGE

STATE_PASSPHRASE=$(openssl rand -base64 48)

WIREGUARD_SERVER_PRIVATE_KEY=$(wg genkey)
WIREGUARD_WORKSTATION_PRIVATE_KEY=$(wg genkey)
WIREGUARD_WORKSTATION_PUBLIC_KEY=$(printf '%s' "$WIREGUARD_WORKSTATION_PRIVATE_KEY" | wg pubkey)

step "encrypting secrets to $secrets_dir"
mkdir -p "$secrets_dir"
export STATE_PASSPHRASE
export WIREGUARD_SERVER_PRIVATE_KEY WIREGUARD_WORKSTATION_PUBLIC_KEY WIREGUARD_WORKSTATION_PRIVATE_KEY
bash scripts/encrypt-sops.sh "$secrets_dir/state.sops.yaml" json -- jq -n '{
    TF_VAR_encryption_passphrase: env.STATE_PASSPHRASE,
    AWS_ACCESS_KEY_ID: env.S3_AK, AWS_SECRET_ACCESS_KEY: env.S3_SK
}'
bash scripts/encrypt-sops.sh "$secrets_dir/tofu.sops.yaml" json -- jq -n '{
    TF_VAR_hcloud_token: env.HCLOUD_TOKEN, TF_VAR_cloudflare_api_token: env.CF_TOKEN,
    TF_VAR_cloudflare_web_analytics_api_token: env.CF_ACCOUNT_TOKEN,
    TF_VAR_cloudflare_primary_email: env.CF_PRIMARY_EMAIL,
    TF_VAR_cloudflare_gmail_email: env.CF_GMAIL_EMAIL,
    TF_VAR_cloudflare_proton_email: env.CF_PROTON_EMAIL,
    TF_VAR_s3_access_key_id: env.S3_AK, TF_VAR_s3_secret_access_key: env.S3_SK,
    TF_VAR_wanderbound_upload_s3_credential_project_id: env.UPLOAD_PROJECT_ID,
    TF_VAR_wanderbound_upload_s3_access_key_id: env.UPLOAD_ACCESS_KEY_ID,
    SENTRY_AUTH_TOKEN: env.SENTRY_AUTH_TOKEN,
    TAILSCALE_OAUTH_CLIENT_ID: env.TS_OAUTH_ID, TAILSCALE_OAUTH_CLIENT_SECRET: env.TS_OAUTH_SECRET
}'
bash scripts/encrypt-sops.sh "$secrets_dir/wireguard.sops.yaml" json -- jq -n '{
    TF_VAR_wireguard_server_private_key: env.WIREGUARD_SERVER_PRIVATE_KEY,
    TF_VAR_wireguard_workstation_public_key: env.WIREGUARD_WORKSTATION_PUBLIC_KEY
}'
bash scripts/encrypt-sops.sh "$secrets_dir/workstation.sops.yaml" json -- jq -n '{
    WIREGUARD_WORKSTATION_PRIVATE_KEY: env.WIREGUARD_WORKSTATION_PRIVATE_KEY
}'

step "encrypting Flux GitHub App credentials"
bash scripts/encrypt-sops.sh "$flux_secret" json -- jq -n '{
    apiVersion: "v1", kind: "Secret", type: "Opaque",
    metadata: {namespace: "flux-system", name: "flux-github-app"},
    stringData: {
        githubAppID: env.FLUX_APP_ID,
        githubAppInstallationID: env.FLUX_APP_INSTALLATION_ID,
        githubAppPrivateKey: env.FLUX_APP_PRIVATE_KEY
    }
}'
printf '%s' "$FLUX_APP_ID" | gh secret set FLUX_APP_ID --repo "$repo"
printf '%s\n' "$FLUX_APP_PRIVATE_KEY" | gh secret set FLUX_APP_PRIVATE_KEY --repo "$repo"

unset STATE_PASSPHRASE HCLOUD_TOKEN S3_AK S3_SK CF_TOKEN CF_ACCOUNT_TOKEN
unset CF_PRIMARY_EMAIL CF_GMAIL_EMAIL CF_PROTON_EMAIL TS_OAUTH_ID TS_OAUTH_SECRET
unset UPLOAD_PROJECT_ID UPLOAD_ACCESS_KEY_ID SENTRY_AUTH_TOKEN
unset FLUX_APP_ID FLUX_APP_INSTALLATION_ID FLUX_APP_PRIVATE_KEY FLUX_APP_PRIVATE_KEY_FILE
unset WIREGUARD_SERVER_PRIVATE_KEY WIREGUARD_WORKSTATION_PRIVATE_KEY WIREGUARD_WORKSTATION_PUBLIC_KEY

step "applying repository rulesets"
gh api --method DELETE "repos/$repo/branches/main/protection" >/dev/null 2>&1 || true
for id in $(gh api "repos/$repo/rulesets" --jq '.[].id'); do
  gh api --method DELETE "repos/$repo/rulesets/$id" >/dev/null
done
for f in .github/rulesets/*.json; do
  gh api --method POST "repos/$repo/rulesets" --input "$f" >/dev/null
done

step "done. next: commit and push."
