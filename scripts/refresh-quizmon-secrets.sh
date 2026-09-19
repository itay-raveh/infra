#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."

mode=${1:-}
if [[ "$mode" != database && "$mode" != release ]] ||
   [[ "$mode" == release && $# != 2 ]] ||
   [[ "$mode" == database && $# != 1 ]]; then
    printf 'usage: refresh-quizmon-secrets.sh database | release <existing-worker-secrets.json>\n' >&2
    exit 2
fi

temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
bash scripts/tofu-wrapper.sh output -json quizmon_inputs > "$temporary/inputs.json"
worker_file=${2:-$temporary/worker.json}
if [[ "$mode" == database ]]; then printf '{}\n' > "$worker_file"; fi
jq -e --arg mode "$mode" --slurpfile worker "$worker_file" \
    -f scripts/quizmon-inputs.jq "$temporary/inputs.json" > "$temporary/secrets.json"

directory="clusters/shire/apps/quizmon/$mode/inputs"
bash scripts/encrypt-sops.sh "$directory/generated.sops.yaml" json -- cat "$temporary/secrets.json"

if [[ "$mode" == release ]]; then
    revision=$(sha256sum "$temporary/secrets.json" | cut -d ' ' -f 1)
    jq --arg revision "$revision" '
        def input($name; $key): {name: $name, key: $key, revision: $revision};
        {apiVersion: "v1", kind: "ConfigMap",
         metadata: {namespace: "quizmon", name: "quizmon-runtime",
                    labels: {"reconcile.fluxcd.io/watch": "Enabled"}},
         data: {"values.yaml": ({
           runtimeConfig: {hyperdriveId: .hyperdrive_id},
           inputs: {
             workerSecrets: input("quizmon-worker"; "worker-secrets.json"),
             cloudflare: input("quizmon-cloudflare"; "cloudflare.json"),
             migrationConnection: input("quizmon-migration"; "migration-connection.json")
           },
           powersync: {
             sourceSecret: input("quizmon-sync-source"; "uri"),
             storageSecret: input("quizmon-sync-storage"; "uri")
           }
         } | tojson)}}
    ' "$temporary/inputs.json" > "$temporary/runtime.yaml"
    mv "$temporary/runtime.yaml" "$directory/runtime.yaml"
fi

yq -i '.resources |= (. + ["generated.sops.yaml"] | unique)' "$directory/kustomization.yaml"
if [[ "$mode" == release ]]; then
    yq -i '.resources |= (. + ["runtime.yaml"] | unique)' "$directory/kustomization.yaml"
fi
printf 'Updated Quizmon %s inputs. Review and commit the encrypted manifests.\n' "$mode"
