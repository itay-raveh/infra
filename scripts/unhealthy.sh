#!/usr/bin/env bash
set -euo pipefail

kubectl get pods -A -o json | jq -r '
    ["NAMESPACE", "POD", "PHASE", "REASON"],
    (.items[] |
        select(.status.phase != "Succeeded") |
        select(.status.phase != "Running" or
            all(.status.conditions[]?; .type != "Ready" or .status != "True")) |
        [.metadata.namespace, .metadata.name, .status.phase,
            ([.status.initContainerStatuses[]?, .status.containerStatuses[]?] |
                map(.state.waiting.reason // empty) | join(","))]) |
    @tsv
'
