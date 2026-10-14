# Phase 4: Synthesis (2026-10-14)

Evidence paths are relative to `research/self-hosted-cicd/proof-linux/`. "Lab" = disposable KVM VMs (QEMU inside the
`cicd-vmlab` container, Ubuntu 24.04 guests, Docker 29.1.3), see `../phase-1/scope.md`.

## 1. VERIFIED / NOT VERIFIED — Mac claims

| # | Mac claim | Linux result | Evidence |
|---|---|---|---|
| M1 | `render.py small/medium/large`: 8 files each, 0 YAML/JSON errors; budgets S 13.25/16, M 27.5/32, L 54/64 GB | **VERIFIED** (identical numbers; also `shared-verify` 10.25/12 and `--host`) | `q02-render/render.txt`, `final-static-checks.txt` |
| M2 | `agent-gate.sh` blocks `commit --no-verify`, `commit -n`, `push --no-verify`; allows `push -n`, `git log -n`; blocks push on failing check; Stop gives up after 3 | **VERIFIED**, now also in a **real Claude Code session** (not only a fake `task`). Nuance: `push -n` is allowed only when `task check` passes (the push gate applies to dry-runs) | `q10-gates/agent-gate-claude-session.txt`, `agent-gate-direct.txt` |
| M3 | Phase 6: `bash -n` passes on all scripts; all YAML parses | **VERIFIED**; new: actionlint 1.7.12 rejects `concurrency.queue` in `hardened-ci.yml` (reference only) | `q02-render/final-static-checks.txt` |
| M4 | TOML, nftables, Caddyfile templates never machine-checked | **Now VERIFIED**: `nft -c -f` OK, `caddy validate` "Valid configuration", `tomllib` OK (both the Mac originals and the fixed templates) | `q02-render/nft-check.txt` |
| M5 | Forgejo 15 LTS supported to 2027-07-15; v16 current | **VERIFIED** (docs); 15.0.10 is the latest patch and runs in the lab; v16 is non-LTS with EOL 2026-10-29 → stay on 15 | `../phase-2/discovery.md` §1, `q03-forge/versions-admin-validate.txt` |
| M6 | forge compose: rootless `15-rootless`, uid 1000, no-new-privileges, SSH 2222, curl healthcheck | **VERIFIED** (healthy; git over SSH :2222 used for every push) | `q03-forge/compose-up.txt`, `q08-cd-tier1/repo-setup.txt` |
| M7 | Registration off, sign-in required, private by default, Actions + packages on | **VERIFIED** (sign-up "Registration is disabled", anonymous API 403, orgs/repos private) | `q03-forge/allowlist.txt` |
| M8 | Caddy `tls internal`, allow-list, admin off; publishes 443 | **VERIFIED** (outsider 403, trusted/runner/target 200). **Fixed**: binds `${FORGE_BIND_IP}` not 0.0.0.0; allow-list must include deploy targets | `q03-forge/allowlist.txt` |
| M9 | registry:3 Docker Hub pull-through mirror (domain root, Docker Hub only) | **VERIFIED**: dind pulled `library/golang`, `library/postgres`, `moby/buildkit` through it; gcr.io went direct (Docker Hub only, as documented) | `q03-forge/mirror-catalog.txt` |
| M10 | Optional Postgres (M/L) vs SQLite (S) | **VERIFIED** both (Postgres in the main run; SQLite/small healthy in 32 s; `depends_on … required: false` works on Compose 2.40) | `q03-forge/compose-up.txt`, `sqlite-small-profile.txt` |
| M11 | runner-vm: two lanes, each its own privileged dind, on 172.30.10/20.0/24 | **VERIFIED** (inside the runner VM only) | `q04-runner/compose-up.txt` |
| M12 | Tokens via compose secrets + `token_url: file:$CREDENTIALS_DIRECTORY/…` | **VERIFIED** (v13.2.0 schema; "declared successfully") | `q04-runner/compose-up.txt`, `runner13-default-config.yaml` |
| M13 | Runner uid 1001 | **WRONG** → image uid is 1000; template fixed | `q04-runner/runner13-default-config.yaml` (id), Phase 2 |
| M14 | runner-ci: capacity = CI_SLOTS, per-job memory/CPU/pids limits, no bind mounts, force_pull, cache on 172.30.10.10 | **VERIFIED**: job cgroup memory.max 3 GiB, swap 0, cpu 2, pids 4096; `[/] is not a valid volume, will be ignored`; cache hits (Q6) | `q04-runner/limits-volumes-cache.txt` |
| M15 | runner-deploy: separate registration + dockerd, cache off | **VERIFIED** (2 GiB/1 CPU limits, no `ACTIONS_CACHE_URL`) | same |
| M16 | `nftables.conf.tmpl` `inet ci_egress`: internet + forge + DNS, RFC1918/CGNAT refused, deploy→SSH targets | **VERIFIED** 12/12 per lane from job containers. **Fixed**: public DNS/DoT were allowed (now refused) | `q05-egress/` |
| M17 | `inet ci_egress` evaluated before Docker's rules | **VERIFIED** on Docker 29.1.3 / iptables-nft: our forward hook at `filter - 1`, Docker's `FORWARD` at `filter` | `q05-egress/nft-ordering.txt` |
| M18 | 100.64/10 in the private set; Tailscale-IP forge works because accept precedes reject | 100.64/10 refusal **VERIFIED**; forge-on-Tailscale-IP case **NOT RUN** (lab forge on 10.77/24 — the same accept-before-reject order is exercised there) | `q05-egress/` |
| M19 | `tls internal` needs the Caddy root CA in dind, runner (`SSL_CERT_FILE`) and both images | **VERIFIED and corrected**: `SSL_CERT_DIR` (not `SSL_CERT_FILE`), dind needs it via env too (certs.d alone fails on Docker 29), hosts need the system store, BuildKit needs `--buildkitd-config` | `q07-images/build-push.txt`, `../phase-3/deep-dive.md` #8, #11 |
| M20 | Taskfile names are the contract (`check:fast`/`check`/`ci`/`image`) | **VERIFIED** with a from-scratch Go Taskfile called from L0–L4. The repo-template's pnpm commands were **NOT RUN** (example stack) | `q06-cache/run7-…log`, `q10-gates/` |
| M21 | prek config (pre-commit-hooks v6.0.0, gitleaks v8.30.1, actionlint v1.7.12, zizmor v1.30.1, local task check on pre-push) | **VERIFIED** (prek 0.5.5; zizmor not in the app config → **NOT RUN**). **Fixed**: actionlint needs `-config-file` for `.forgejo` | `q10-gates/prek-l1-l2.txt` |
| M22 | pipeline.yml: `ci` on `runs-on: ci` with postgres service; checkout/cache SHA-pinned | **VERIFIED** (Postgres-backed integration test ran in CI). Pins bumped: checkout v6.1.0, cache v5.1.0 | `q06-cache/run7-…log` |
| M23 | `release` on `runs-on: deploy`, main only, bot PAT, buildx push by digest + provenance + SBOM, `kamal deploy --skip-push` | **VERIFIED** after 2 fixes (BuildKit CA, `service` label) | `q08-cd-tier1/run4-…`, `run11-…` |
| M24 | Kamal health-gated: old version keeps serving on failure | **VERIFIED**: 963/963 requests 200 from the old version while the new one failed `/up` | `q08-cd-tier1/run26-…`, `serve-loop-…log` |
| M25 | Deploy-repo `promote.yml` + `apps.allow`, re-checks CI for the exact SHA | **VERIFIED** after a fix (combined state → CI context) | `q09-cd-tier2/promote.txt` |
| M26 | Forgejo has no environment-scoped secrets; same-repo branch workflows can read repo secrets | **VERIFIED** (branch `agent/secrets-demo` got `REGISTRY_TOKEN` length 40 + the deploy key on the deploy lane) | `q09-cd-tier2/branch-secrets-demo.log` |
| M27 | Automatic token can't push packages → bot PAT `write:package` | **VERIFIED**: generic upload 401 `reqPackageAccess`, OCI push 401; the bot PAT pushes but gets 403 on code/repo creation | `q07-images/automatic-token-push.log`, `bot-pat-scope.txt` |
| M28 | `data.forgejo.org` mirrors github.com/actions with identical SHAs | **VERIFIED** (`git ls-remote`; the lab resolved every pin from data.forgejo.org) | Phase 2 S217, CI logs |
| M29 | Runner v13 requires Docker ≥ 25; removed `::set-output`/`set-env`/`add-path` | **VERIFIED (docs)**; lab used Docker 29 only, the removed commands were not exercised | Phase 2 S213 |
| M30 | Capacity > 1 on one dockerd lets concurrent jobs see each other | **NOT RUN** (shared-verify uses 1 ci slot) | — |
| M31 | `upload-artifact@v4` needs Forgejo's fork; `permissions:` / `continue-on-error` ignored; concurrency best-effort | **NOT RUN** | — |
| M32 | Podman/pasta can't reach the runner cache server | **NOT RUN** (Docker only) | — |
| M33 | Kamal `deploy` user in docker group is root-equivalent; dedicate the key | Design note, applied (dedicated `deploy` user + key generated in the runner VM) | `q08-cd-tier1/target-setup.txt` |
| M34 | Footprint numbers (idle RAM, start latency, cache speed) are estimates | **Replaced by measurements** (§3) | `q11-measure/` |
| M35 | 8-step bring-up runbook (README §4) | **VERIFIED** for steps 1–6 and 8; step 7 (GitHub lane) NOT RUN. Runbook rewritten with the Linux findings | `../phase-5/README.md` §4 |
| M36 | GitHub hybrid lane (`GITHUB_SLOTS`, `gh-runner@`, phase-6 JIT launcher, GARM, ARC), GitHub-lane dates/fees | **NOT RUN** (out of scope: needs GitHub App/org credentials) | — |
| M37 | Alternative B Woodpecker + Cloudflare tunnel | **NOT RUN** (out of scope) | — |
| M38 | Optional advisory LLM-review job via the home LLM gateway | **NOT RUN** (the nftables exception stays templated; nothing wired to the live gateway) | — |
| M39 | Gitea 1.27 near-tie | **NOT RUN** (Q12); note Gitea is now versioned v28.x | Phase 2 §9 |

## 2. VERIFIED / NOT VERIFIED — brief questions

| Q | Result |
|---|---|
| Q1 host fit | **VERIFIED**: 16 threads, 31 GB (18.8 GB available, ~12.3 GB co-tenants), 800 GB free, KVM usable, Docker 29.8.1; nominal M, small by free capacity; added `shared-verify` (FREE floors: 6 threads / 12 GB / 100 GB) + `render.py --host` + `detect-host.sh` |
| Q2 render + machine checks | **VERIFIED**: render on Linux clean for all 4 profiles; `nft -c`, `caddy validate`, TOML, actionlint, shellcheck |
| Q3 forge VM | **VERIFIED**: Postgres + SQLite variants healthy; allow-list 403 from outside; Forgejo 15.0.10 latest LTS patch; v16 non-LTS (EOL 2026-10-29), changes listed in Phase 2 |
| Q4 runner VM | **VERIFIED**: both lanes registered via `forgejo-cli actions register` (40-hex) + `server.connections`; `runs-on: ci`/`deploy` routing held in 40+ jobs; ci lane cannot reach the deploy dockerd (probe) and holds no deploy secrets. Caveat: any job in a repo that HAS secrets can reference them regardless of lane (M26) — the lane split protects the daemon, the deploy-repo pattern protects the secrets |
| Q5 egress | **VERIFIED** 12/12 per lane (internet, forge 443 + SSH, DNS only via RUNNER_DNS, RFC1918 + 100.64/10 refused, SSH to targets from deploy lane only); table ordering before Docker on iptables-nft |
| Q6 cache | **VERIFIED**: v4.3.0, v5.1.0, v6.1.0 all `cache-hit=true` on run 2 (v1 protocol); v4.3.0's node20 declaration does not matter (ran on the image's Node 24.21.0). App CI cold 5m15s → warm 1m42s; `go vet` step 96 s → 0.5 s; 50 MB restore < 1 s |
| Q7 images | **VERIFIED**: ci-base/deploy-base built, pushed with a `write:package`-only bot PAT, digest-pinned in site.env, pulled by the runners with a separate `read:package` PAT; automatic token denied (401) |
| Q8 CD Tier 1 | **VERIFIED**: merge → build + push by digest → Kamal deploy; health-gated (failed `/up` → old version kept serving, 0 errors); rollback via `kamal rollback` (0 errors) |
| Q9 CD Tier 2 | **VERIFIED**: promote refuses a non-allow-listed app and a SHA without green CI, deploys a valid one; deploy runner re-scoped to `infra/deploy` only (the app repo's release job is left `pending` with no runner) |
| Q10 gates | **VERIFIED**: branch protection blocks merging a red PR (405), direct and force push; prek L1 (private key, gofmt) and L2 (`task check` on pre-push) block locally; agent gate in a real Claude Code 2.1.299 session; the `args` exec-form hook schema is valid (kept) |
| Q11 measure | **VERIFIED** — §3 |
| Q12 Gitea swap-in | **NOT RUN** (optional; time) |

## 3. Measurements (lab; shared-verify profile)
| Component | Idle RAM (docker stats) | Template limit |
|---|---|---|
| Forgejo 15.0.10 (Postgres backend, ~45 jobs of history) | 193 MiB | 768 MiB |
| Postgres 17.11 | 47 MiB | 384 MiB |
| Caddy 2.11.7 | 18 MiB | — |
| registry:3 mirror | 24 MiB | 256 MiB |
| Forgejo SQLite variant (fresh) | 99 MiB | 768 MiB |
| runner-ci / runner-deploy (v13.2.0) | 8 MiB each fresh (32 MiB after jobs) | 256 MiB |
| dind-ci / dind-deploy (29) | 36 / 30 MiB fresh; 658 / 230 MiB after builds (page cache counted) | 3.5 / 2.5 GiB |
| kamal-proxy v0.9.2 / app container | 4.3 MiB / 1.3 MiB | — |
| Guest "used" (free -m): forge VM / runner VM / target VM | 658 / 856 / 406 MB | VM 3 / 6 / 1.25 GB |
| **QEMU RSS on the host** (what the box pays) | 3.1 / 6.2 / 1.3 GB = **10.6 GB** (guests fill RAM with page cache; no balloon) | |

Timings: job start latency (dispatch → runner pickup) 1.3–1.8 s, → first step running 2.2–2.8 s, both lanes
(5 samples, fetch interval 2 s). CI (Go app, 1 ci slot = 2 vCPU/3 GB): first run 5m15s (image pulls + cold module
cache), warm 1m37s–1m47s (8 runs), failing PR 11 s. Release (1 deploy slot = 1 vCPU): 5m54s–7m35s, of which ~2 min
is pulling the Go base image into a fresh BuildKit builder and ~3 min is `go build` on 1 vCPU; Kamal itself
6.6 s. Rollback 9 s. Forge stack first start 130 s incl. pulls; runner lanes `up --wait` 8 s.
Profiles: the forge-side limits stay (they are peak budgets, not idle) but the measured idle values are recorded
in `profiles/shared-verify.env`'s header; RAM accounting must use whole-VM sizes (QEMU RSS ≈ allocation).

## 4. Cross-topic notes
- **#1 ubuntu-deploy-platform conflict (documented, not merged):** its `forgejo-deploy.yml.tmpl` assumes a runner
  ON the web host with Docker access calling `bin/ship` (kamal-proxy + grype/syft/cosign + registry:3 on
  127.0.0.1:5000). This topic deploys from a runner **VM** deploy lane with Kamal over SSH, pushing to the Forgejo
  registry. An on-host runner contradicts "runner in a VM, never on the host". Both keep working; a merged design
  would be: deploy lane in the runner VM SSHes to the web host and runs `bin/ship` there (backlog).
- **Registry decision stays OPEN** (Forgejo OCI here, registry:3 in #1, Zot in #2). Lab facts that matter for the
  decision: Forgejo's registry needs a PAT per pusher (no automatic-token push), private packages need pull
  credentials on every runner and host; registry:3 in proxy mode is read-only.
- #16 llm-code-quality-gates: plugs into `check`/`ci` Taskfile tasks or an advisory L3 job (the nftables exception
  for the gateway route stays templated).
- #4 observability-factory: scrape points would be Forgejo `/metrics` (not enabled), runner logs, Kamal/kamal-proxy.

## 5. Live-host changes
No host packages, sudo, units, sysctl, firewall, bridges or Docker daemon config. Docker objects created on the live
Docker (all removable): image `cicd-vmlab:1` (+ base `ubuntu:24.04`), container `cicd-vmlab` (`--rm`, `/dev/kvm` +
`/dev/net/tun`, `NET_ADMIN` in its own netns, no ports, default bridge), images pulled for validation
`data.forgejo.org/forgejo/runner:13`, `koalaman/shellcheck:v0.11.0` (if not present), short-lived `--rm` containers
`cicdv-runner-gencfg*`, `cicdv-shellcheck`. Files: `research/self-hosted-cicd/lab/state/` (VM disks ~15 GB, lab
keys/secrets — never published), session scratchpad (task/gitleaks/actionlint binaries, agent-gate scratch repo).
One outward action: the public repo (see STATUS.md). Approval: none was requested (none of these is a host
configuration change); the lab container is flagged in STATUS.md as a judgment call the user can veto.
