#!/usr/bin/env bash
# Wrapper that decrypts SOPS secrets into env vars before running tofu.
# Usage: bash scripts/tofu-wrapper.sh <subcommand> [args...]
#
# YubiKey touch-policy "cached" (15s) means one touch covers the decrypt.
# When rops gains age-plugin support (gibbz00/rops#17), replace this script
# with a single [env] line: _.file = "tofu/secrets.sops.yaml"
set -euo pipefail
set -a
eval "$(sops decrypt --output-type dotenv tofu/secrets.sops.yaml)"
set +a
tofu -chdir=tofu "$@"
