#!/usr/bin/env bash
# joblog.sh <owner/repo> <task-id> — raw job log from Forgejo's log storage (zstd once the task finished)
t=$2; d=$(printf '%02x' $((t % 256)))
f=/var/lib/gitea/actions_log/$1/$d/$t.log
docker exec ci-forge-forgejo-1 sh -c "cat $f.zst 2>/dev/null" | zstd -dc 2>/dev/null || docker exec ci-forge-forgejo-1 cat "$f"
