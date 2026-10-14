#!/usr/bin/env bash
# latency.sh <owner/repo> <workflow.yml> <n> — dispatch -> runner pickup -> first step running, per run
S=~/lab-secrets
for i in $(seq 1 $3); do
  t0=$(date +%s.%N)
  curl -sS --cacert ~/caddy-root.crt -H "Authorization: token $(cat $S/admin.token)" -H 'Content-Type: application/json' \
    -X POST "https://git.lab.test/api/v1/repos/$1/actions/workflows/$2/dispatches" -d '{"ref":"main"}' -o /dev/null
  sleep 3; bash ~/scripts/wait.sh "$1" 300 >/dev/null
  t=$(bash ~/scripts/tasks.sh "$1" | head -1); id=$(echo "$t" | cut -f1)
  log=$(bash ~/scripts/joblog.sh "$1" "$id")
  first=$(echo "$log" | head -1 | cut -c1-30); main=$(echo "$log" | grep -m1 -E '⭐ Run Main' | cut -c1-30); end=$(echo "$log" | tail -1 | cut -c1-30)
  python3 - "$t0" "$first" "$main" "$end" "$id" <<'P'
import sys,datetime as d
t0=float(sys.argv[1]); f=lambda s: d.datetime.fromisoformat(s.strip().rstrip('Z')[:26]).replace(tzinfo=d.timezone.utc).timestamp()
a,b,c=f(sys.argv[2]),f(sys.argv[3]),f(sys.argv[4])
print(f"task {sys.argv[5]}: dispatch->runner picked up {a-t0:5.1f}s | ->first step running {b-t0:5.1f}s | total job {c-t0:5.1f}s")
P
done
