#!/usr/bin/env bash
set -euo pipefail
umask 077

if (($# < 4)) || [[ "$3" != -- ]]; then
    printf 'usage: encrypt-sops.sh <target> <input-type> -- <producer> [<arg> ...]\n' >&2
    exit 2
fi
target=$1
input_type=$2
shift 3

if [[ -d "$target" ]]; then
    printf 'error: target is a directory: %s\n' "$target" >&2
    exit 1
fi
temporary=$(mktemp "${target}.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$@" | sops encrypt --filename-override "$target" --input-type "$input_type" > "$temporary"
mv -f -- "$temporary" "$target"
