#!/usr/bin/env bash
# sync-push.sh <branch> <message> — copy the app from ~/xfer-hello into the working copy on <branch>
# (based on origin/<branch> if it exists, else origin/main), commit, push
set -euo pipefail
b=$1; m=$2; cd ~/work/hello
git fetch -q origin
if git rev-parse -q --verify "origin/$b" >/dev/null; then git checkout -q -B "$b" "origin/$b"; else git checkout -q -B "$b" origin/main; fi
rsync -a --delete --exclude .git ~/xfer-hello/ ./
git add -A; git commit -qm "$m"; git push -q origin "$b" 2>&1 | grep -v -E '^remote: *$|^remote: (Create|Visit|  )' || true
git log --oneline -1
