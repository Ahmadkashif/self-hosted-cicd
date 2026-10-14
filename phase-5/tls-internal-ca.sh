#!/usr/bin/env bash
# tls-internal-ca.sh <root.crt> <domain>...  — lay out a Caddy `tls internal` root CA for Docker daemons:
# creates ./ca/certs.d/<domain>/ca.crt next to root.crt (mount at /etc/docker/certs.d) for each domain.
set -euo pipefail
ca="$1"; shift; dir="$(dirname "$ca")/certs.d"
grep -q 'BEGIN CERTIFICATE' "$ca" || { echo "not a PEM certificate: $ca" >&2; exit 1; }
for d in "$@"; do mkdir -p "$dir/$d"; cp "$ca" "$dir/$d/ca.crt"; done
echo "certs.d for: $*"
