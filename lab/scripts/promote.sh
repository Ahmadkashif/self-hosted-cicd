#!/usr/bin/env bash
# promote.sh <app> <sha> — dispatch infra/deploy promote, wait, print result + key log lines
S=~/lab-secrets
curl -sS --cacert ~/caddy-root.crt -H "Authorization: token $(cat $S/admin.token)" -H 'Content-Type: application/json' \
  -X POST https://git.lab.test/api/v1/repos/infra/deploy/actions/workflows/promote.yml/dispatches \
  -d "{\"ref\":\"main\",\"inputs\":{\"app\":\"$1\",\"sha\":\"$2\"}}" -w "dispatch promote app=$1 sha=${2:0:10} -> HTTP %{http_code}\n"
sleep 4; bash ~/scripts/wait.sh infra/deploy 900 >/dev/null
t=$(bash ~/scripts/tasks.sh infra/deploy | head -1); echo "$t" | cut -f1-7
bash ~/scripts/joblog.sh infra/deploy "$(echo "$t" | cut -f1)" > ~/promote-$(echo "$t" | cut -f1).log
grep -E "not in apps.allow|CI '|bad sha|pushed |kamal-proxy deploy|Finished all|ERROR|🏁" ~/promote-$(echo "$t" | cut -f1).log | cut -c30-220
