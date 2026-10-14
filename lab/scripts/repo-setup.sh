#!/usr/bin/env bash
# INSIDE the forge VM ("developer workstation" + admin). Sets repo vars/secrets for apps/hello, an SSH key for git.
set -euo pipefail
S=~/lab-secrets
api() { m=$1; p=$2; shift 2; curl -fsS --cacert ~/caddy-root.crt -X "$m" -H "Authorization: token $(cat $S/admin.token)" \
          -H 'Content-Type: application/json' "https://git.lab.test/api/v1$p" "$@"; }
R=/repos/apps/hello
for kv in REGISTRY_HOST=git.lab.test REGISTRY_USER=ci-bot; do
  k=${kv%%=*}; v=${kv#*=}; api POST $R/actions/variables/$k -d "{\"value\":\"$v\"}" >/dev/null 2>&1 || api PUT $R/actions/variables/$k -d "{\"value\":\"$v\"}" >/dev/null
done
api PUT $R/actions/secrets/REGISTRY_TOKEN -d "$(jq -n --rawfile d $S/bot-pkg.token '{data: ($d|rtrimstr("\n"))}')" -o /dev/null -w "secret REGISTRY_TOKEN: %{http_code}\n"
api PUT $R/actions/secrets/DEPLOY_SSH_KEY -d "$(jq -n --rawfile d $S/deploy_key '{data: $d}')" -o /dev/null -w "secret DEPLOY_SSH_KEY: %{http_code}\n"
api GET $R/actions/variables | jq -c '[.[]|{name,data}]'
# git over SSH (Forgejo's built-in sshd, published on FORGE_BIND_IP:2222)
[ -f ~/.ssh/id_dev ] || ssh-keygen -q -t ed25519 -N '' -C dev-workstation -f ~/.ssh/id_dev
api POST /user/keys -d "$(jq -n --rawfile k ~/.ssh/id_dev.pub '{title:"dev-workstation", key:$k}')" >/dev/null 2>&1 || true
cat > ~/.ssh/config <<C
Host git.lab.test
  Port 2222
  User git
  IdentityFile ~/.ssh/id_dev
  StrictHostKeyChecking accept-new
C
git config --global user.name "Lab Developer"; git config --global user.email dev@lab.test; git config --global init.defaultBranch main
ssh -T git.lab.test 2>&1 | head -2 || true
