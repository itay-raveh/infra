#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
case "$mode" in
    on|off|status) ;;
    *) printf 'usage: mise run quizmon:maintenance -- on|off|status\n' >&2; exit 2 ;;
esac
: "${TF_VAR_cloudflare_api_token:?missing Cloudflare API token}"

zone_id=4be281e220538b2ad2def80f8f5150a5
entrypoint="https://api.cloudflare.com/client/v4/zones/$zone_id/rulesets/phases/http_request_dynamic_redirect/entrypoint"
cloudflare() {
    curl --fail-with-body --silent --show-error \
        --config <(printf 'header = "Authorization: Bearer %s"\n' "$TF_VAR_cloudflare_api_token") \
        "$@"
}

current=$(cloudflare "$entrypoint")
rule=$(jq -ce '[.result.rules[]? | select(.ref == "quizmon_maintenance")] | if length == 1 then .[0] else error("Quizmon maintenance rule is missing or duplicated") end' <<< "$current")
enabled=$(jq -r '.enabled' <<< "$rule")

if [[ "$mode" == status ]]; then
    printf 'Quizmon maintenance: %s\n' "$([[ "$enabled" == true ]] && printf on || printf off)"
    exit
fi

target=false
[[ "$mode" == on ]] && target=true
if [[ "$enabled" != "$target" ]]; then
    ruleset_id=$(jq -r '.result.id' <<< "$current")
    rule_id=$(jq -r '.id' <<< "$rule")
    payload=$(jq -c --argjson enabled "$target" '{ref, description, expression, action, action_parameters, enabled: $enabled}' <<< "$rule")
    cloudflare --request PATCH --header 'Content-Type: application/json' \
        --data "$payload" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/rulesets/$ruleset_id/rules/$rule_id" > /dev/null
fi

verified=$(cloudflare "$entrypoint" | jq -r '.result.rules[] | select(.ref == "quizmon_maintenance") | .enabled')
[[ "$verified" == "$target" ]] || { printf 'Maintenance rule did not reach %s\n' "$mode" >&2; exit 1; }
printf 'Quizmon maintenance: %s\n' "$mode"
