#!/usr/bin/env bash
# wait.sh <owner/repo> [timeout-s] — wait until no task is waiting/running, then print the latest tasks
for i in $(seq 1 $(( ${2:-900} / 10 ))); do
  out=$(bash ~/scripts/tasks.sh "$1" 8)
  echo "$out" | grep -q -E '	(running|waiting|blocked)	' || break; sleep 10
done
echo "$out"
