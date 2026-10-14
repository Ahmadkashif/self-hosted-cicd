#!/usr/bin/env bash
# Runs INSIDE a throwaway dev container (ci-base image + python3) on the forge VM. L1/L2 hooks via prek.
set -uo pipefail
apt-get update -qq >/dev/null && apt-get install -y -qq python3 python3-venv >/dev/null 2>&1
cd /tmp && curl -fsSLO https://github.com/j178/prek/releases/download/v0.5.5/prek-x86_64-unknown-linux-gnu.tar.gz \
  && curl -fsSL https://github.com/j178/prek/releases/download/v0.5.5/prek-x86_64-unknown-linux-gnu.tar.gz.sha256 | sha256sum -c - >/dev/null \
  && tar -xzf prek-x86_64-unknown-linux-gnu.tar.gz && install prek-x86_64-unknown-linux-gnu/prek /usr/local/bin/ && prek --version
git config --global user.email dev@lab.test; git config --global user.name dev; git config --global init.defaultBranch main
git init -q --bare /tmp/origin.git
cp -r /src /tmp/hello && cd /tmp/hello && rm -rf .git && git init -q && git add -A && git commit -qm base && git remote add origin /tmp/origin.git && git push -q origin main
echo '$ prek install --hook-type pre-commit --hook-type pre-push'; prek install --hook-type pre-commit --hook-type pre-push
echo; echo '=== L1: commit a file with a private key (expect BLOCK)'
h="OPENSSH PRIV""ATE KEY"   # fake fixture, header assembled at runtime so secret scanners don't flag this file
printf -- "-----BEGIN $h-----\nZmFrZS1rZXktbWF0ZXJpYWwtZm9yLWEtaG9vay10ZXN0LW5vdC1hLXJlYWwta2V5Cg==\n-----END $h-----\n" > deploy_key
git add deploy_key; t0=$(date +%s); git commit -qm "add key" 2>&1 | grep -E 'Failed|Passed|detect private key|gitleaks|leaks found' | head -8; echo "commit exit=${PIPESTATUS[0]} ($(( $(date +%s)-t0 ))s incl. first-run hook install)"; git reset -q HEAD deploy_key; rm -f deploy_key
echo; echo '=== L1: commit a badly formatted Go file (expect BLOCK)'
printf 'package main\nfunc  badlyFormatted( ) {}\n' > cmd/hello/bad.go; git add cmd/hello/bad.go
t0=$(date +%s); git commit -qm "bad fmt" 2>&1 | grep -E 'Failed|Passed|gofmt' | tail -3; echo "commit exit=${PIPESTATUS[0]} ($(( $(date +%s)-t0 ))s)"; git reset -q HEAD cmd/hello/bad.go; rm -f cmd/hello/bad.go
echo; echo '=== L1: clean commit (expect PASS)'
echo "Clean change." >> README.md; git add -A; t0=$(date +%s); git commit -qm "clean" 2>&1 | grep -E 'Failed|Passed' | head -12; echo "commit exit=${PIPESTATUS[0]} ($(( $(date +%s)-t0 ))s)"
echo; echo '=== L2: break a unit test, commit with --no-verify (skips L1), then git push (expect BLOCK by task check)'
sed -i 's/want 200 ok/want 200 ok (broken)/; s/rec.Code != http.StatusOK ||/rec.Code != http.StatusTeapot ||/' cmd/hello/main_test.go
git commit -qam "break test" --no-verify; git fetch -q origin
t0=$(date +%s); git push origin main 2>&1 | grep -E 'task check|FAIL|Failed|Passed|rejected|error: failed' | head -8; echo "push exit=${PIPESTATUS[0]} ($(( $(date +%s)-t0 ))s)"
echo "remote main still at: $(git --git-dir=/tmp/origin.git log --oneline -1 main)"
echo; echo '=== L2: fix and push (expect PASS)'
git checkout -q HEAD~1 -- cmd/hello/main_test.go; git commit -qam "fix test"; t0=$(date +%s); git push origin main 2>&1 | grep -E 'task check|Failed|Passed|->' | head -6; echo "push exit=${PIPESTATUS[0]} ($(( $(date +%s)-t0 ))s)"
