#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    setup_fakebin
    export TF_VAR_cloudflare_api_token=fixture
    export RESPONSE="$BATS_TEST_TMPDIR/response.json"
    export PATCH_PAYLOAD="$BATS_TEST_TMPDIR/payload.json"
    export PATCH_URL="$BATS_TEST_TMPDIR/url"
    cat > "$RESPONSE" <<'JSON'
{"result":{"id":"ruleset","rules":[{"id":"other","ref":"redirect_apex_to_itay","enabled":true},{"id":"maintenance","ref":"quizmon_maintenance","description":"Maintenance","expression":"http.host eq \"quizmon.raveh.dev\"","action":"redirect","action_parameters":{"from_value":{"status_code":302,"target_url":{"value":"https://quizmon.raveh.dev/maintenance"}}},"enabled":false}]}}
JSON
    cat > "$FAKEBIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
method=GET
while (($#)); do
    case "$1" in
        --request) method=$2; shift 2 ;;
        --data) payload=$2; shift 2 ;;
        *) url=$1; shift ;;
    esac
done
if [[ "$method" == PATCH ]]; then
    printf '%s\n' "$payload" > "$PATCH_PAYLOAD"
    printf '%s\n' "$url" > "$PATCH_URL"
    jq --argjson enabled "$(jq -r '.enabled' "$PATCH_PAYLOAD")" '.result.rules[1].enabled = $enabled' "$RESPONSE" > "$RESPONSE.next"
    mv "$RESPONSE.next" "$RESPONSE"
fi
cat "$RESPONSE"
SH
    make_executable "$FAKEBIN/curl"
}

@test "maintenance command toggles only the Quizmon redirect and reports its state" {
    run bash scripts/quizmon-maintenance.sh status
    [ "$status" -eq 0 ]
    [ "$output" = "Quizmon maintenance: off" ]

    run bash scripts/quizmon-maintenance.sh on
    [ "$status" -eq 0 ]
    [ "$output" = "Quizmon maintenance: on" ]
    [ "$(cat "$PATCH_URL")" = "https://api.cloudflare.com/client/v4/zones/4be281e220538b2ad2def80f8f5150a5/rulesets/ruleset/rules/maintenance" ]
    jq -e '.ref == "quizmon_maintenance" and .enabled == true and .action_parameters.from_value.status_code == 302' "$PATCH_PAYLOAD"
    jq -e '.result.rules[0].enabled == true' "$RESPONSE"

    run bash scripts/quizmon-maintenance.sh off
    [ "$status" -eq 0 ]
    [ "$output" = "Quizmon maintenance: off" ]
    jq -e '.enabled == false' "$PATCH_PAYLOAD"
}
