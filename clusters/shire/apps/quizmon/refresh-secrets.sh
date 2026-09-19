#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/../../../.."
app_dir=clusters/shire/apps/quizmon

mode=${1:-}
if [[ "$mode" != database && "$mode" != release ]] ||
   [[ "$mode" == release && $# != 2 ]] ||
   [[ "$mode" == database && $# != 1 ]]; then
    printf 'usage: refresh-secrets.sh database | release <existing-worker-secrets.json>\n' >&2
    exit 2
fi

temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
bash scripts/tofu-wrapper.sh output -json quizmon_inputs > "$temporary/inputs.json"
worker_file=${2:-$temporary/worker.json}
if [[ "$mode" == database ]]; then printf '{}\n' > "$worker_file"; fi
jq -e --arg mode "$mode" --slurpfile worker "$worker_file" \
    -f "$app_dir/inputs.jq" "$temporary/inputs.json" > "$temporary/secrets.json"

directory="$app_dir/$mode/inputs"
while IFS= read -r name; do
    jq --arg name "$name" '.[] | select(.metadata.name == $name)' \
        "$temporary/secrets.json" > "$temporary/$name.json"
    sops encrypt --filename-override "$directory/$name.sops.yaml" --input-type json --output-type yaml \
        "$temporary/$name.json" > "$temporary/$name.sops.yaml"
done < <(jq -r '.[].metadata.name' "$temporary/secrets.json")

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
fi

jq --arg mode "$mode" '{
  apiVersion: "kustomize.config.k8s.io/v1beta1", kind: "Kustomization",
  resources: ([.[].metadata.name + ".sops.yaml"] + if $mode == "release" then ["runtime.yaml"] else [] end)
}' "$temporary/secrets.json" | yq -P > "$temporary/kustomization.yaml"
mv "$temporary/"*.yaml "$directory/"
printf 'Updated Quizmon %s inputs. Review and commit the encrypted manifests.\n' "$mode"
