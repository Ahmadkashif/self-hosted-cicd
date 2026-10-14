#!/usr/bin/env bash
# build-images.sh <registry-host>/<org> <tag> [extra-ca.crt]  — build ci-base + deploy-base, push, print digests.
# Log in first with the bot PAT (write:package only):  docker login <registry-host> -u ci-bot --password-stdin
# Paste the printed CI_IMAGE / DEPLOY_IMAGE lines into site.env and re-render.
set -euo pipefail
repo="$1"; tag="$2"; ca="${3:-}"
here="$(cd "$(dirname "$0")" && pwd)"
for img in ci-base deploy-base; do
  rm -rf "$here/$img/ca"; mkdir -p "$here/$img/ca"
  [ -n "$ca" ] && cp "$ca" "$here/$img/ca/extra-ca.crt"
  # --load + `docker push` (not `buildx --push`): the daemon honours /etc/docker/certs.d/<registry>/ca.crt for a
  # private CA (Caddy `tls internal`); BuildKit's own push path did not (Docker 29.1, lab 2026-10-14).
  docker buildx build --pull --load --provenance=false -t "$repo/$img:$tag" "$here/$img" >&2
  docker push "$repo/$img:$tag" >&2
  digest="$(docker inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$repo/$img:$tag" | grep -m1 "^$repo/$img@" | cut -d@ -f2)"
  var=$([ "$img" = ci-base ] && echo CI_IMAGE || echo DEPLOY_IMAGE)
  echo "$var=$repo/$img:$tag@$digest"
done
