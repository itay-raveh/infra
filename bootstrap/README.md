# bootstrap/

`cluster-age-key.sops.txt` — the cluster software age key, encrypted to the
YubiKeys only (not to itself). Unwrapped into a `sops-age` Secret in
`flux-system` during every cluster rebuild. See `docs/setup.md`.
