#!/usr/bin/env bash
# tasks.sh <owner/repo> [n] — list recent Actions tasks (jobs) via the Forgejo API
S=~/lab-secrets
curl -fsS --cacert ~/caddy-root.crt -H "Authorization: token $(cat $S/admin.token)" \
  "https://git.lab.test/api/v1/repos/$1/actions/tasks?limit=${2:-10}" |
  jq -r '.workflow_runs[] | [.id, .run_number, .name, .event, .head_branch, (.head_sha[0:10]), .status, .run_started_at, .updated_at] | @tsv'
