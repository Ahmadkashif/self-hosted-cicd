# Phase 3: Deep dive — build and end-to-end verification (2026-10-14)

Working tree: `phase-5/` (copied from `mac-source/phase-5`, all fixes made in templates and `render.py`, never in
rendered output), `app/` (verification repos written from scratch), `lab/` (VM lab + helper scripts),
`proof-linux/qNN-*/` (transcripts). Lab topology and the no-host-change decision: `../phase-1/scope.md`.

## 3.1 Sequence actually executed
1. `detect-host.sh` (new) → host facts; `shared-verify` profile + co-tenant budget (`render.py --host`) → Q1.
2. Built `cicd-vmlab:1`, started it (`--rm`, no ports, not privileged), booted forge/runner/target VMs from the
   sha256-verified Ubuntu 24.04 cloud image, installed Docker 29.1.3 + compose 2.40.3 inside each (`q00-lab/`).
3. Rendered all profiles; `nft -c -f` (runner VM), `caddy validate` (forge VM), `tomllib` (host) on both the
   unmodified Mac templates and the fixed ones → Q2 (`q02-render/`).
4. Forge: `COMPOSE_PROFILES=postgres docker compose … up -d` → healthy in 130 s incl. pulls; Forgejo 15.0.10,
   Postgres 17.11, Caddy 2.11.7, distribution 3.1.2. Admin via `forgejo admin user create`. Allow-list test from
   four source addresses. SQLite/small variant in an isolated copy → healthy in 32 s → Q3 (`q03-forge/`).
5. Orgs `infra`/`apps`, bot `ci-bot` in a `registry-push` team (packages write, code read), PATs: `write:package`,
   `read:package` (runner pulls), `read:repository` (promote) (`q07-images/forge-setup.txt`).
6. ci-base / deploy-base built from `phase-5/images/` and pushed with the `write:package` PAT; digests into the lab
   site file; re-render (`q07-images/build-push.txt`).
7. Runner VM: 40-hex secrets generated there, `forgejo-cli actions register` on the forge (ci → org `apps`,
   deploy → repo `apps/hello`), UUIDs into the site file, re-render, nftables loaded via `nftables.service`,
   `compose.yaml + compose.tls-internal.yaml up` → both lanes "declared successfully" → Q4 (`q04-runner/`).
8. Target VM: dedicated `deploy` user (docker group), key generated in the runner VM, CA in system trust.
9. Verification app `apps/hello` (Go, from scratch) pushed over Forgejo SSH :2222; branch protection; PR flow;
   Tier 1 releases; failing health check; rollback; secrets-gap demo; Tier 2 switch and promotes (`q08-`, `q09-`, `q10-`).
10. Probe repo `apps/probe` + `infra/deploy` egress workflow: egress/isolation from job containers in both lanes,
    cache matrix ×2, automatic-token push (`q05-`, `q06-`, `q07-`).
11. prek L1/L2 in a throwaway dev container (ci-base + python) in the forge VM; agent gate in a real headless
    Claude Code session on the host against a scratch copy of the app (`q10-gates/`).
12. Measurements: idle RAM (container + guest + QEMU RSS), job latency ×5, job durations (`q11-measure/`).

## 3.2 Bugs found on Linux and fixed in the templates
| # | Where | Problem (evidence) | Fix |
|---|---|---|---|
| 1 | `runner-vm/compose.yaml` | Runner image runs as uid **1000** (`id` in image; Dockerfile v13.2.0), template forced 1001 | `user: "1000:1000"`, comments |
| 2 | profiles | `docker:28-dind` frozen since 2025-11-05 (Phase 2) | `DIND_TAG=29-dind` (dind 29 used in the lab) |
| 3 | `runner-*.yaml.tmpl` | Runbook said "paste the UUID into the rendered YAML" = hand-editing rendered output | `uuid: ${RUNNER_CI_UUID}` / `${RUNNER_DEPLOY_UUID}` from site.env |
| 4 | `runner-vm/compose.yaml` | dind had no healthcheck: runners exited "cannot ping the docker daemon" and restart-looped (`q04-runner/compose-up.txt`) | dind healthcheck + `depends_on: condition: service_healthy`; re-verified: 0 ping errors, `up --wait` 8 s |
| 5 | `forge-host/compose.yaml` | `443:443` and `${FORGE_SSH_PORT}:2222` on 0.0.0.0 collide with anything else on :443 (Tailscale serve) | `${FORGE_BIND_IP}:…` + `FORGE_BIND_IP` in site.env |
| 6 | `Caddyfile.tmpl` | Kamal makes the **target** pull from the forge registry; targets were not in the allow-list | `${DEPLOY_TARGETS}` added to the allow-list (target → 200 verified) |
| 7 | `nftables.conf.tmpl` | "DNS only via RUNNER_DNS" not enforced for **public** resolvers: the final `accept` let 1.1.1.1:53 / DoT through | `meta l4proto {tcp,udp} th dport {53,853} reject` after the RUNNER_DNS accept; counters show 8 rejected packets in the probes |
| 8 | TLS option (c) | `SSL_CERT_FILE` replaces the system roots (would break fetching actions from data.forgejo.org); dind had no CA; Docker 29 (containerd store) ignores `/etc/docker/certs.d` for the registry **token** endpoint: `docker login` OK, push `x509: unknown authority` (`q07-images/build-push.txt`) | `compose.tls-internal.yaml` overlay: runners + dind get `SSL_CERT_DIR=/etc/ssl/certs:/run/ca` (+ certs.d via `tls-internal-ca.sh`); hosts use the system store + docker restart (README §4.2) |
| 9 | runner lanes | Job images are private forge packages; the runner had no pull credentials | `DOCKER_CONFIG=/run/registry-pull` + `secrets/registry-pull/config.json` (read:package PAT); jobs cannot see it (probe: `/run/registry-pull` absent in job) |
| 10 | `repo-template` Taskfile + prek | actionlint auto-discovers `.github/actionlint.yaml` only for `.github/workflows`; on `.forgejo/workflows` labels `ci`/`deploy` were "unknown" (first CI run failed: `q10-gates/run1-ci-actionlint-fail.log`) | `-config-file .github/actionlint.yaml` in Taskfile + prek hook; `repo-template/.github/actionlint.yaml` added |
| 11 | `pipeline.yml` release | BuildKit's docker-container driver runs in its own container without the private CA | `--buildkitd-config` with `[registry."<host>"] ca=[…]` from the CA baked into deploy-base |
| 12 | `pipeline.yml` release | Kamal refuses an image without label `service=<service>` (Kamal's own builder adds it; the template's buildx did not) | `--label service=$(… deploy.yml service)` |
| 13 | `promote.yml` | Checked the **combined** commit state; with any other context pending (the app's own release job without a runner) it is `pending`, so valid SHAs would be refused (`q09-cd-tier2/promote.txt`: combined=pending, ci=success) | check the named CI context (`CI_CONTEXT`, default `pipeline / ci (push)`) |
| 14 | `promote.yml` | `kamal deploy --version` builds with Kamal's builder (same CA problem, no attestations) | explicit buildx push by digest (+label, CA) then `kamal deploy --skip-push`; quiet cleanup |
| 15 | README | Required check named `pipeline / ci`; Forgejo's context is `pipeline / ci (pull_request)` | runbook §4.7 |
| 16 | pins | checkout v6.0.2 lacks 2026-07-20 fixes; cache v4.3.0 is node20 | checkout **v6.1.0** `d23441a4…`; cache **v5.1.0** `caa29612…` (v4.3.0/v5.1.0/v6.1.0 all verified) |
| 17 | `render.py` | Profiles hard-coded to S/M/L; no notion of co-tenants or a forge in a VM | any `profiles/*.env`; `--host` co-tenant budget; `FORGE_PLACEMENT=vm` with forge/target VM sizes |
| 18 | new | No host detection; no base-image definitions | `detect-host.sh`; `images/{ci-base,deploy-base}` + `build-images.sh` (load + `docker push`, digest printed) |

Not template bugs, but recorded:
- Forgejo reports **skipped** jobs as `success` statuses (`pipeline / release (pull_request)=success`): never make a
  conditional job a required check.
- Kamal 2.12.0 boots **kamal-proxy v0.9.2** by default (latest tag v0.10.2).
- Cross-lane dockerd probes **time out** rather than get the nftables reject: Docker 29's own raw/isolation rules
  drop the packet first. Blocked either way.
- `mac-source/phase-6/templates/workflows/hardened-ci.yml` uses `concurrency.queue`, which actionlint 1.7.12 rejects
  (reference-only file, GitHub syntax not verified here).
- Two bugs were mine (verification app), caught by the gates: an unquoted `: ` in a prek hook entry (prek refused
  to parse the config) and the deliberate port change.

## 3.3 Done-criteria walk-through (app `apps/hello`, from scratch)
| Step | What happened | Evidence |
|---|---|---|
| 1 push | Initial push over Forgejo SSH (:2222) | `q08-cd-tier1/initial-push.txt` |
| 2 red PR blocked | PR #1 `TestVersionIsJSON` failed in 11 s; merge API → **405 "Not all required status checks successful"**; direct push and force push to main rejected | `q10-gates/pr1-red-blocked.txt`, `branch-protection.txt` |
| 3 green + cache hit | Fix → green in 1m42s; `Cache restored from key: go-b56c…` (50 MB) | `q06-cache/run7-pr1-ci-green-warm.log` |
| 4 merge → deploy | Merge → ci 1m37s → release: buildx push by digest `sha256:d2780e61…`, Kamal deploy, `hello from 9f4dae9…` served | `q08-cd-tier1/run11-…log`, `after-merge-serving.txt` |
| 5 broken health | PR #3 (listen on 8080; unit tests green) → release failed "target failed to become healthy within 20s"; **963/963 requests 200 from the old version** | `q08-cd-tier1/run26-…log`, `serve-loop-…log` |
| + rollback | `rollback.yml` (deploy lane) → `kamal rollback 9f4dae9…` in 9 s, 0 failed requests over 1021 | `q08-cd-tier1/rollback.log` |
| 6 Tier 2 | Deploy runner re-scoped to `infra/deploy`; app secrets deleted; promote refused (a) app not in apps.allow, (b) SHA without green CI; (c) deployed `839d8dd…` | `q09-cd-tier2/` |
| 7 egress | 12/12 probes pass in each lane from job containers | `q05-egress/` |
| 8 agent gate | Real Claude Code session: `--no-verify` blocked, push blocked by red `task check`, Stop blocked ×3 then released | `q10-gates/agent-gate-claude-session.txt` |

## 3.4 Not run
Q12 Gitea swap-in (optional; time). GitHub lane, Woodpecker, LLM-review job (out of scope). DNS-01/Tailscale TLS
modes (only `tls internal` exercised). osv-scanner/semgrep/syft/grype tasks of the repo-template Taskfile (the
verification app's contract doesn't call them; BuildKit's syft scanner did produce the SBOM attestation). Backups,
L5 jobs, per-job VMs.
