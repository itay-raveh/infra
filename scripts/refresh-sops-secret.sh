#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == --render ]]; then
    ns=$2
    name=$3
    key=$4
    shift 4
    "$@" | jq -Rs --arg ns "$ns" --arg name "$name" --arg key "$key" '
        if length == 0 then error("secret producer returned an empty value") else
            {apiVersion: "v1", kind: "Secret", metadata: {namespace: $ns, name: $name},
             data: {($key): (. | @base64)}}
        end
    '
    exit
fi

if (($# < 6)) || [[ "$5" != -- ]]; then
    printf 'usage: refresh-sops-secret.sh <target> <namespace> <name> <key> -- <producer> [<arg> ...]\n' >&2
    exit 2
fi
target=$1
ns=$2
name=$3
key=$4
shift 5

bash "$(dirname "$0")/encrypt-sops.sh" "$target" json -- \
    bash "$0" --render "$ns" "$name" "$key" "$@"
printf 'wrote %s\n' "$target" >&2
