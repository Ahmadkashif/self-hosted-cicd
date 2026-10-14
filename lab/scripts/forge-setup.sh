#!/usr/bin/env bash
# Runs INSIDE the forge VM. Creates orgs, the bot user and scoped tokens. Secrets go to ~/lab-secrets (0600), never printed.
set -euo pipefail
S=~/lab-secrets; umask 077
F="docker exec ci-forge-forgejo-1 forgejo"
api() { m=$1; p=$2; shift 2; curl -fsS --cacert ~/caddy-root.crt -X "$m" -H "Authorization: token $(cat $S/admin.token)" \
          -H 'Content-Type: application/json' "https://git.lab.test/api/v1$p" "$@"; }
[ -s $S/admin.token ] || $F admin user generate-access-token --username forgeadmin --token-name lab-admin --scopes all --raw > $S/admin.token
for o in infra apps; do api POST /orgs -d "{\"username\":\"$o\",\"visibility\":\"private\"}" >/dev/null 2>&1 || true; done
api GET /orgs/infra | jq -c '{org:.username, visibility}'; api GET /orgs/apps | jq -c '{org:.username, visibility}'
[ -s $S/bot.pw ] || { openssl rand -hex 16 > $S/bot.pw; $F admin user create --username ci-bot --email ci-bot@lab.test --password "$(cat $S/bot.pw)" --must-change-password=false >/dev/null; }
# a team per org that may push packages (no code write)
for o in infra apps; do
  tid=$(api GET /orgs/$o/teams | jq -r '.[]|select(.name=="registry-push").id')
  [ -n "$tid" ] || tid=$(api POST /orgs/$o/teams -d '{"name":"registry-push","permission":"read","units_map":{"repo.packages":"write","repo.code":"read","repo.actions":"read"},"includes_all_repositories":true}' | jq -r .id)
  api PUT /teams/$tid/members/ci-bot >/dev/null
  echo "org $o team registry-push id=$tid members=$(api GET /teams/$tid/members | jq -r '[.[].login]|join(",")') units=$(api GET /teams/$tid | jq -c .units_map)"
done
# bot PAT: write:package ONLY (Basic auth as the bot, as a user would create it in the UI)
if [ ! -s $S/bot-pkg.token ]; then
  curl -fsS --cacert ~/caddy-root.crt -u "ci-bot:$(cat $S/bot.pw)" -H 'Content-Type: application/json' \
    -X POST https://git.lab.test/api/v1/users/ci-bot/tokens -d '{"name":"registry-push","scopes":["write:package"]}' | jq -r .sha1 > $S/bot-pkg.token
  curl -fsS --cacert ~/caddy-root.crt -u "ci-bot:$(cat $S/bot.pw)" -H 'Content-Type: application/json' \
    -X POST https://git.lab.test/api/v1/users/ci-bot/tokens -d '{"name":"registry-pull","scopes":["read:package"]}' | jq -r .sha1 > $S/bot-pull.token
  curl -fsS --cacert ~/caddy-root.crt -u "ci-bot:$(cat $S/bot.pw)" -H 'Content-Type: application/json' \
    -X POST https://git.lab.test/api/v1/users/ci-bot/tokens -d '{"name":"app-read","scopes":["read:repository"]}' | jq -r .sha1 > $S/bot-read.token
fi
curl -fsS --cacert ~/caddy-root.crt -u "ci-bot:$(cat $S/bot.pw)" https://git.lab.test/api/v1/users/ci-bot/tokens | jq -c '.[]|{name,scopes}'
ls -l $S | awk '{print $1, $NF}'
