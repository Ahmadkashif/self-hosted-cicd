#!/usr/bin/env bash
# agent-gate.sh — L0 gate for AI coding agents (Claude Code hooks; exit 2 = block / keep working).
#   stop      : when the agent tries to finish, run `task check:fast`; on failure feed the errors back (exit 2).
#               Gives up after 3 consecutive forced continuations so a stuck agent hands over to a human.
#   pre-bash  : before any Bash call containing `git push`, require `task check` to have passed for HEAD;
#               refuse `--no-verify` outright.
# Template — review before use. Needs: bash, git, task, python3 (JSON parsing of the hook input).
set -uo pipefail
mode="${1:-stop}"
input="$(cat)"
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
state_dir="$(git rev-parse --git-dir 2>/dev/null)/agent-gate" || exit 0
mkdir -p "$state_dir"

json() { printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }

case "$mode" in
  stop)
    session="$(json 'd.get("session_id","x")')"; session="${session:-x}"
    active="$(json 'str(d.get("stop_hook_active", False)).lower()')"
    counter="$state_dir/stop-$session.count"
    [ "$active" = "true" ] || echo 0 > "$counter"
    n="$(cat "$counter" 2>/dev/null || echo 0)"
    if [ "$n" -ge 3 ]; then
      echo "agent-gate: check:fast still failing after 3 attempts; stopping so a human can look." >&2
      exit 0
    fi
    fingerprint="$(git rev-parse HEAD)-$( (git diff HEAD; git ls-files --others --exclude-standard) | git hash-object --stdin)"
    [ -f "$state_dir/fast-$fingerprint" ] && exit 0
    if out="$(task check:fast 2>&1)"; then
      touch "$state_dir/fast-$fingerprint"; echo 0 > "$counter"; exit 0
    fi
    echo $((n + 1)) > "$counter"
    printf 'task check:fast failed. Fix these before finishing:\n%s\n' "$(printf '%s' "$out" | tail -n 80)" >&2
    exit 2
    ;;
  pre-bash)
    cmd="$(json 'd.get("tool_input",{}).get("command","")')"
    case "$cmd" in *"git "*) ;; *) exit 0 ;; esac
    # --no-verify skips hooks for commit and push; for `git commit` (only) -n means the same thing.
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(commit|push)[^;&|]*--no-verify' \
       || printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+commit[^;&|]*[[:space:]]-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
      echo "agent-gate: skipping hooks (--no-verify / commit -n) is not allowed for agents." >&2
      exit 2
    fi
    printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push' || exit 0
    head="$(git rev-parse HEAD)"
    [ -f "$state_dir/check-$head" ] && exit 0
    if out="$(task check 2>&1)"; then
      touch "$state_dir/check-$head"; exit 0
    fi
    printf 'agent-gate: `task check` failed on %s; push blocked:\n%s\n' "$head" "$(printf '%s' "$out" | tail -n 80)" >&2
    exit 2
    ;;
esac
exit 0
