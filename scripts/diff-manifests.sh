#!/usr/bin/env bash
set -euo pipefail

base=${1:?Usage: mise run manifests:diff -- <git-ref>}
git rev-parse --verify "$base^{commit}" > /dev/null
kubernetes_version=$(sed -n 's/.*kubernetes_version *= "v\([^"]*\)"/\1/p' tofu/locals.tf)
# Avoid the parallel-render hang: https://github.com/home-operations/flate/issues/828
flate diff all --concurrency 1 --path clusters/shire --base "$base" --kube-version "$kubernetes_version" --skip-schema-validation --no-progress -o github
