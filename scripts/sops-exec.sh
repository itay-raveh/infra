#!/usr/bin/env bash
set -euo pipefail

files=()
while (($#)) && [[ "$1" != -- ]]; do
    files+=("$1")
    shift
done
if ((${#files[@]} == 0 || $# < 2)); then
    printf 'usage: sops-exec.sh <file> [<file> ...] -- <command> [<arg> ...]\n' >&2
    exit 2
fi
shift

# SOPS runs its command through /bin/sh, which cannot parse Bash's printf %q.
quote_command() {
    local argument
    printf 'exec'
    for argument in "$@"; do
        printf " '%s'" "${argument//\'/\'\\\'\'}"
    done
}

command=$(quote_command "$@")
for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        printf 'error: missing encrypted file: %s\n' "$file" >&2
        exit 1
    fi
    while IFS= read -r key; do
        unset "$key"
        command=": \"\${$key:?missing $key}\"; $command"
    done < <(sed -nE '/^sops:/d; s/^([A-Za-z_][A-Za-z0-9_]*):.*/\1/p' "$file")
done

for ((index=${#files[@]} - 1; index > 0; index--)); do
    command=$(quote_command sops exec-env --same-process "${files[index]}" "$command")
done
exec sops exec-env --same-process "${files[0]}" "$command"
