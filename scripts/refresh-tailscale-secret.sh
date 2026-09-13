#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == --render ]]; then
    bash scripts/tofu-wrapper.sh output -json | jq -e '
        .tailscale_operator_oauth_client_id.value as $id |
        .tailscale_operator_oauth_client_secret.value as $secret |
        if ($id | type) != "string" or ($id | length) == 0 or
           ($secret | type) != "string" or ($secret | length) == 0 then
            error("state is missing Tailscale operator credentials")
        else
            {apiVersion: "v1", kind: "Secret",
             metadata: {namespace: "tailscale", name: "operator-oauth"},
             data: {client_id: ($id | @base64), client_secret: ($secret | @base64)}}
        end
    '
    exit
fi

target=clusters/shire/infrastructure/controllers/tailscale-operator-oauth.sops.yaml
bash scripts/encrypt-sops.sh "$target" json -- bash scripts/refresh-tailscale-secret.sh --render
printf 'wrote %s\n' "$target" >&2
