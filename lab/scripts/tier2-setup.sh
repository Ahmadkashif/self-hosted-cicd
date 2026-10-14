#!/usr/bin/env bash
# INSIDE the forge VM: move CD secrets from apps/hello to infra/deploy; re-scope the deploy runner to infra/deploy.
set -euo pipefail
S=~/lab-secrets
api() { m=$1; p=$2; shift 2; curl -sS --cacert ~/caddy-root.crt -X "$m" -H "Authorization: token $(cat $S/admin.token)" \
          -H 'Content-Type: application/json' "https://git.lab.test/api/v1$p" "$@"; }
echo "$ forgejo forgejo-cli actions register --name runner-deploy-shared-verify --scope infra/deploy --secret <same 40-hex>"
docker exec ci-forge-forgejo-1 forgejo forgejo-cli actions register --name runner-deploy-shared-verify --scope infra/deploy --secret "$(cat $S/rsec-deploy)"; echo
rm -f $S/rsec-deploy
R=/repos/infra/deploy
for kv in REGISTRY_HOST=git.lab.test REGISTRY_USER=ci-bot; do k=${kv%%=*}; v=${kv#*=}; api POST $R/actions/variables/$k -d "{\"value\":\"$v\"}" -o /dev/null; done
api PUT $R/actions/secrets/REGISTRY_TOKEN -d "$(jq -n --rawfile d $S/bot-pkg.token '{data: ($d|rtrimstr("\n"))}')" -o /dev/null -w "infra/deploy secret REGISTRY_TOKEN: %{http_code}\n"
api PUT $R/actions/secrets/APP_READ_TOKEN -d "$(jq -n --rawfile d $S/bot-read.token '{data: ($d|rtrimstr("\n"))}')" -o /dev/null -w "infra/deploy secret APP_READ_TOKEN: %{http_code}\n"
api PUT $R/actions/secrets/DEPLOY_SSH_KEY -d "$(jq -n --rawfile d $S/deploy_key '{data: $d}')" -o /dev/null -w "infra/deploy secret DEPLOY_SSH_KEY: %{http_code}\n"
for k in REGISTRY_TOKEN DEPLOY_SSH_KEY; do api DELETE /repos/apps/hello/actions/secrets/$k -o /dev/null -w "apps/hello delete secret $k: %{http_code}\n"; done
echo "apps/hello secrets now: $(api GET /repos/apps/hello/actions/secrets | jq -c '[.[].name]')"
echo "infra/deploy secrets now: $(api GET /repos/infra/deploy/actions/secrets | jq -c '[.[].name]')"
