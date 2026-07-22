#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    INGRESS_ROUTE=clusters/shire/apps/wanderbound/ingressroute.yaml
}

@test "uses single-argument Traefik method matchers for media" {
    route=$(yq -r '.spec.routes[] | select(.middlewares[]?.name == "wanderbound-media-limit") | .match' "$INGRESS_ROUTE")

    [[ "$route" == *"Method(\`GET\`)"* ]]
    [[ "$route" == *"Method(\`HEAD\`)"* ]]
    [[ "$route" == *'||'* ]]
}
