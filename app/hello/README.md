# hello — verification app for the self-hosted CI/CD blueprint

A deliberately small Go service written from scratch to exercise the blueprint end to end:
`GET /up` (kamal-proxy health check), `GET /` (version), `GET /visits` (Postgres counter).

| Task | What | Called by |
|---|---|---|
| `task check:fast` | gofmt, go vet, unit tests | Claude Code Stop hook (L0) |
| `task check` | check:fast + gitleaks (range) + actionlint | prek pre-push (L2), agent-gate before `git push` |
| `task ci` | check + Postgres integration test + image build | Forgejo `runs-on: ci` (L3) |
| `task image` | `docker buildx build --load` | CI; the release job builds + pushes by digest (L4) |
