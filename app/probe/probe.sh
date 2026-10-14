#!/usr/bin/env bash
# probe.sh <lane> — egress + isolation probes, run INSIDE a job container. Prints one line per probe:
#   PASS/FAIL  <probe>  expected=<open|refused>  got=<open|refused|timeout>
# Lab addresses (lab/vmlab): forge 10.77.0.10, target 10.77.0.30, LAN "NAS" 10.77.0.1:8080, CGNAT 100.64.0.1:8080.
lane="$1"; fails=0
tcp() { # host port -> open|refused|timeout
  local out; out=$(timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>&1); local rc=$?
  if [ $rc -eq 0 ]; then echo open; elif [ $rc -eq 124 ]; then echo timeout; else echo "refused"; fi
}
check() { # name expected got
  local ok=FAIL; { [ "$2" = "$3" ] || { [ "$2" = refused ] && [ "$3" = timeout ]; }; } && ok=PASS
  [ "$2" = refused ] && [ "$3" = timeout ] && ok="PASS(timeout)"
  [ "$ok" = FAIL ] && fails=$((fails+1)); printf '%-14s %-44s expected=%-8s got=%s\n' "$ok" "$1" "$2" "$3"
}
http() { curl -sS -m 8 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || echo 000; }
echo "lane=$lane container=$(hostname) resolv=$(grep -m1 nameserver /etc/resolv.conf)"
code=$(http https://proxy.golang.org/); check "internet https://proxy.golang.org" open "$([ "$code" != 000 ] && echo open || echo refused)"
code=$(http https://git.lab.test/api/healthz); check "forge https git.lab.test:443 (/api/healthz=$code)" open "$([ "$code" = 200 ] && echo open || echo refused)"
check "forge ssh 10.77.0.10:2222" open "$(tcp 10.77.0.10 2222)"
ip=$(getent hosts git.lab.test | awk '{print $1}'); check "DNS via RUNNER_DNS: git.lab.test -> ${ip:-none}" open "$([ "$ip" = 10.77.0.10 ] && echo open || echo refused)"
check "DNS to public resolver 1.1.1.1:53/tcp" refused "$(tcp 1.1.1.1 53)"
check "DoT to public resolver 9.9.9.9:853" refused "$(tcp 9.9.9.9 853)"
check "RFC1918 LAN service 10.77.0.1:8080" refused "$(tcp 10.77.0.1 8080)"
check "CGNAT/Tailscale range 100.64.0.1:8080" refused "$(tcp 100.64.0.1 8080)"
check "deploy target app 10.77.0.30:80" refused "$(tcp 10.77.0.30 80)"
if [ "$lane" = deploy ]; then
  check "deploy target SSH 10.77.0.30:22 (deploy only)" open "$(tcp 10.77.0.30 22)"
  check "OTHER lane dockerd 172.30.10.2:2375 (ci)" refused "$(tcp 172.30.10.2 2375)"
else
  check "deploy target SSH 10.77.0.30:22 (deploy only)" refused "$(tcp 10.77.0.30 22)"
  check "OTHER lane dockerd 172.30.20.2:2375 (deploy)" refused "$(tcp 172.30.20.2 2375)"
fi
own=$(docker -H tcp://dind.docker.internal:2375 info --format '{{.Name}}' 2>/dev/null || echo none)
check "own lane dockerd via DOCKER_HOST (name=$own)" open "$([ "$own" != none ] && echo open || echo refused)"
echo "--- secrets visible to this job (names only)"
env | cut -d= -f1 | grep -E -i 'token|secret|password|key' | sort | tr '\n' ' '; echo
ls -A /run/secrets /run/registry-pull 2>&1 | head -3
echo "probe failures: $fails"; exit $fails
