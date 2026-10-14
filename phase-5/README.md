# Phase 5 — Starter blueprint (templates, verified on Linux 2026-10-14)

Templates for the hardware profiles in `../phase-4/synthesis.md` §5 plus `shared-verify` (a box that already runs
other workloads). `render.py` renders them for one profile and checks the resource budget; it never touches
Docker or the network. **2026-10-14:** the primary stack (forge, both runner lanes, egress policy, cache, registry,
Kamal Tier 1 + Tier 2, gates) was brought up in disposable KVM VMs on a Linux box and driven end to end with a
brand-new app. Evidence: `../proof-linux/`. What is still NOT RUN: §6.

## 1. Layout

```
phase-5/
├── profiles/{small,medium,large,shared-verify}.env   # minimum-host requirements + per-lane slot sizes
├── detect-host.sh                      # READ-ONLY inventory -> suggested profile (+ --env host.env for render.py)
├── site.env.example                    # your names/IPs/subnets/runner UUIDs/image digests (no secrets)
├── render.py                           # budget check (+ co-tenant-aware with --host) + render + syntax check
├── tls-internal-ca.sh                  # lay out the Caddy `tls internal` root CA as certs.d for the dind daemons
├── images/{ci-base,deploy-base}/Dockerfile + build-images.sh   # job images (Node 24 inside: JS actions run there)
├── forge-host/                         # Forgejo 15 LTS (rootless) [+ Postgres] + Caddy + Docker Hub mirror
│   ├── compose.yaml                    # binds ${FORGE_BIND_IP}:443 / :${FORGE_SSH_PORT} (never 0.0.0.0 on a shared box)
│   ├── Caddyfile.tmpl                  # allow-list: admin subnets + runner subnet + deploy targets
│   └── registry-mirror.yml.tmpl
├── runner-vm/                          # INSIDE a dedicated VM on its own bridge/VLAN
│   ├── compose.yaml                    # ci + deploy lanes (+ github), each with its own DinD (healthchecked)
│   ├── compose.tls-internal.yaml       # overlay for Caddy `tls internal`: CA for runners AND dind daemons
│   ├── runner-{ci,deploy}.yaml.tmpl    # Forgejo Runner v13 `server.connections` (uuid from site.env)
│   ├── dind-daemon.json.tmpl, nftables.conf.tmpl (egress: internet + forge + RUNNER_DNS only; RFC1918/CGNAT refused)
│   └── systemd/gh-runner@.service.tmpl, github.env.example   # GitHub hybrid lane (reference only, NOT RUN)
├── repo-template/                      # Taskfile contract, prek, pipeline (ci + release), Kamal, agent gate
├── deploy-repo-template/               # Tier 2: promote.yml + apps.allow
└── alt-woodpecker/                     # Alternative B (reference only, NOT RUN)
```

## 2. Architecture sketch

```
 laptop / AI agent                          home server (host)                         runner VM (own VLAN)
 ──────────────────                         ─────────────────────                      ─────────────────────────────
 L0 Claude hooks ─┐                         Caddy :443 (LAN/Tailscale allow-list)      runner-ci ──poll──┐
 L1 prek commit  ─┼─ task check:fast/check   ├─ Forgejo 15 LTS (git, PRs, Actions,     dind-ci (jobs, no secrets)
 L2 prek push    ─┘                          │   OCI registry)  ◄──── HTTPS poll ───────┤ runner-deploy ─poll─┐
   git push (LAN/Tailscale) ───────────────► ├─ Docker Hub pull-through mirror ◄───────┤ dind-deploy (main only)
                                             └─ push-mirror ──► github.com (showcase)   │ [gh-runner@N ─poll─► github.com]
                                             apps (Kamal targets) ◄── SSH (deploy lane only) ┘
 No inbound from the internet anywhere. Runner VM egress: internet + forge:443/2222 + DNS; RFC1918 refused.
```

## 3. Render (per profile)

```bash
./detect-host.sh --env host.env                         # read-only; suggests a profile by FREE capacity
cp site.env.example site.env && $EDITOR site.env        # domains, IPs, subnets; UUIDs + digests come later
python3 render.py medium --host host.env                # -> build/medium/*, fails if the budget does not fit
```
Budgets (example site): small host 13.25/16 GB, medium 27.5/32, large 54/64, shared-verify 10.25/12
(forge VM 3 + runner VM 6 + target VM 1.25 GB). `--host` additionally refuses the render when the co-tenants leave
too little RAM/threads/disk free right now. `build/<profile>/forge-host.env` / `runner-vm.env` feed `--env-file`.

## 4. Bring-up runbook (executed 2026-10-14 in the QEMU lab; `../proof-linux/` per step)

1. **Hypervisor.** Create the runner VM (`RUNNER_VM_*`) on its own bridge/VLAN with Docker ≥ 25 inside (lab: Ubuntu
   24.04, Docker 29.1.3). Install `build/<p>/nftables.conf` as `/etc/nftables.conf` and enable `nftables.service`
   (it has no `flush ruleset`, so Docker's own tables survive). Snapshot the VM.
2. **TLS** (pick one): (a) DNS-01 ACME with a real domain (recommended); (b) Tailscale certs; (c) Caddy
   `tls internal` — then the root CA (`forge-host/data/caddy/caddy/pki/authorities/local/root.crt`) must go to:
   - every Docker daemon that pulls/pushes (forge admin box, **deploy targets**): the **system** trust store +
     `systemctl restart docker`. `/etc/docker/certs.d` alone is NOT enough on Docker 29 (containerd image store):
     login worked, push failed with `x509: unknown authority` on the token endpoint;
   - the runner VM lanes: `../tls-internal-ca.sh ca/root.crt <forge> <mirror>` and add
     `-f compose.tls-internal.yaml` (runners and dind get `SSL_CERT_DIR=/etc/ssl/certs:/run/ca`; never
     `SSL_CERT_FILE`, which would drop the public roots needed for data.forgejo.org);
   - `images/build-images.sh … root.crt` bakes it into ci-base and deploy-base (+ `NODE_EXTRA_CA_CERTS`);
   - BuildKit's own container in release/promote jobs (the workflows pass it via `--buildkitd-config`).
3. **Forge host.** `secrets/forge.env` (0600) with `FORGEJO_DB_PASSWORD=$(openssl rand -hex 24)`, then
   `COMPOSE_PROFILES=postgres docker compose --env-file ../build/<p>/forge-host.env --env-file secrets/forge.env up -d`
   (omit the profile for SQLite / small). Admin: `forgejo admin user create --admin …`.
4. **Runner registration (IaC).** In the runner VM: `openssl rand -hex 20 > runner-vm/secrets/forgejo_runner_{ci,deploy}_token`.
   On the forge: `forgejo forgejo-cli actions register --name runner-ci-<p> --scope <org> --secret <hex>` → prints a
   UUID → `RUNNER_CI_UUID` in site.env (same for deploy, scoped to the deploying repo(s) only) → re-render. Never
   edit rendered files. Re-running `register` with the same secret and a new `--scope` re-scopes the runner.
5. **Images.** Create a bot user with a PAT of scope `write:package` only (the automatic token cannot push:
   verified 401). `docker login`, then `images/build-images.sh <forge>/infra <tag> [root.crt]` prints
   `CI_IMAGE=…@sha256:…` / `DEPLOY_IMAGE=…` → site.env → re-render. The packages are private, so the runners pull
   them with `runner-vm/secrets/registry-pull/config.json` (a separate `read:package` PAT; jobs never see it).
6. **Runner VM.** `docker compose -f compose.yaml [-f compose.tls-internal.yaml] --env-file ../build/<p>/runner-vm.env up -d --wait`.
7. **Repo settings.** Branch protection on `main`: no push, no force push, required status check
   **`pipeline / ci (pull_request)`** (Forgejo appends the event to `<workflow> / <job>`), apply to admins.
   Tier 1 repo vars `REGISTRY_HOST`, `REGISTRY_USER`; secrets `REGISTRY_TOKEN`, `DEPLOY_SSH_KEY`.
   Deploy targets: a dedicated `deploy` user in the docker group, its key generated in the runner VM, host keys
   committed as `config/known_hosts`.
8. **GitHub lane** (optional, `GITHUB_SLOTS > 0`): unchanged from the Mac research (reference only, NOT RUN here).
9. **Agent gate.** Copy `.claude/settings.json.example` to `.claude/settings.json` (the `args` exec form is valid in
   Claude Code 2.1.x), then `prek install --hook-type pre-commit --hook-type pre-push`.

## 5. Two CD modes (pick per repo)

| Mode | Where secrets live | Deploy trigger | Use when |
|---|---|---|---|
| **Tier 1 — in-repo release job** (`pipeline.yml` `release`) | Forgejo repo secrets + separate deploy lane | Every merge to `main` | Only you (and your agents under your account) can push branches |
| **Tier 2 — deploy-repo pattern** (`deploy-repo-template/`) | Only in `infra/deploy`, whose deploy runner is repo-scoped; app repos hold **zero** secrets | One-click / API `workflow_dispatch` with the app + SHA; CI status re-verified | Unattended agents, collaborators, or anything internet-facing |

Why Tier 2 exists: Forgejo has **no environment-scoped secrets**. The workflow reference has no `environment:`
key, and secrets are withheld only from *fork* PRs. So any same-repo branch workflow can reference a repo secret
and ask for `runs-on: deploy`. In the GitHub lane an `environment:` with a deployment-branch rule (Pro/Team)
closes that gap for secrets. Human approval on private repos needs Enterprise.

## 6. What was validated (2026-10-14, Linux, QEMU/KVM lab) vs. not

VERIFIED (evidence in `../proof-linux/qNN-*`): all four profiles render (0 errors); `nft -c`, `caddy validate`,
TOML, actionlint, shellcheck; forge stack up (Postgres and SQLite variants), health, allow-list 403; both lanes
registered via `forgejo-cli actions register` + `server.connections`; `runs-on` routing; ci lane cannot reach the
deploy dockerd; egress policy from job containers in both lanes; `actions/cache` v4.3.0/v5.1.0/v6.1.0 hits;
ci-base/deploy-base pushed with a `write:package`-only bot PAT, digest-pinned; automatic token denied; Tier 1
release (push by digest, Kamal health-gated deploy, failed health check keeps the old version serving, rollback);
Tier 2 promote (allow-list, CI gate, deploy); branch protection; prek L1/L2; agent gate in a real Claude Code
session; idle RAM and job latency measured.

NOT RUN: the GitHub hybrid lane, Alternative B (Woodpecker), the LLM-review job, per-job VMs, backup/restore and
L5 jobs, Gitea swap-in, a real domain/ACME or Tailscale TLS (only `tls internal`), osv-scanner/semgrep/syft/grype
in the Taskfile contract (the verification app's Taskfile does not use them).
