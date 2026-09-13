#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
    version|-version|-help|--help) exec tofu -chdir=tofu "$@" ;;
esac

files=(secrets/state.sops.yaml)
case "${1:-}" in
    init|output|state|show|workspace) ;;
    *) files+=(secrets/tofu.sops.yaml secrets/wireguard.sops.yaml) ;;
esac
exec bash scripts/sops-exec.sh "${files[@]}" -- tofu -chdir=tofu "$@"
