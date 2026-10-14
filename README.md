# self-hosted-cicd: a home "forge hub" for AI-assisted coding, verified end to end

A fully open-source, fully local CI/CD blueprint for one engineer who codes heavily with AI agents, plus the proof
that it works. **Forgejo 15 LTS** (git, PRs, Actions, OCI registry) sits behind Caddy with an allow-list.
**Forgejo Runner 13** runs in a disposable runner VM with two lanes, each with its own Docker-in-Docker daemon:
`ci` (no secrets) and `deploy` (release only). An **nftables egress policy** lets jobs reach the internet and the
forge but refuses the home LAN. One **Taskfile check contract** (`check:fast` / `check` / `ci` / `image`) is called
by Claude Code hooks, prek git hooks and CI. **Kamal 2** does health-gated deploys over SSH, and a hardened
"deploy repo" lets a human promote a CI-green SHA.

Everything is a template driven by S / M / L / shared-verify hardware profiles. Nothing is hand-fitted to one host.

On 2026-10-14 the stack was brought up in disposable KVM VMs on a Linux box that already runs other workloads.
Nothing on that box was reconfigured. A brand-new Go app was then driven through the whole flow: red PR blocked,
green with a cache hit, merge, deploy, a broken health check that left the old version serving, rollback, a Tier 2
promote, egress tests from job containers, and the agent gate in a real Claude Code session.

## Layout

| Path | What |
|---|---|
| `phase-5/` | **The blueprint.** `profiles/*.env`, `detect-host.sh`, `render.py` (budget check + render), `forge-host/` (Forgejo + Caddy + Docker Hub mirror), `runner-vm/` (two lanes + nftables + `tls internal` overlay), `images/` (ci-base, deploy-base), `repo-template/` (Taskfile contract, prek, pipeline, Kamal, agent gate), `deploy-repo-template/` (Tier 2 promote). Runbook: `phase-5/README.md` |
| `app/hello/` | Verification app written from scratch: Go HTTP service with `/up`, a Postgres-backed integration test, its own Taskfile, a pipeline (ci + Tier 1 release), a rollback workflow, prek config and Claude Code hooks |
| `app/deploy/` | The Tier 2 `infra/deploy` repo used in the lab (promote + allow-list + egress probe) |
| `app/probe/` | Lab probes: egress/isolation (`probe.sh`), `actions/cache` v4/v5/v6 matrix, automatic-token push test, per-job limits |
| `lab/` | The VM lab: `vmlab/` (QEMU/KVM inside one container: no host packages, bridges or firewall changes), `scripts/` (forge setup, PR/promote/latency helpers), `site.lab.env` |
| `proof-linux/qNN-*/` | **Evidence**: command transcripts and job logs per question |
| `phase-1..4/` | Scope, version re-check (sources S200–S238), deep dive (bugs found and fixed), synthesis (VERIFIED / NOT VERIFIED table and measurements) |

## How to run it

**A. Real deployment (your hardware):** follow `phase-5/README.md` §3–§4.

```bash
cd phase-5
./detect-host.sh --env host.env                   # read-only; suggests a profile by FREE capacity
cp site.env.example site.env && $EDITOR site.env  # names, IPs, subnets (no secrets)
python3 render.py medium --host host.env          # budget check + render to build/medium/
# then the runbook: forge host -> register runners (UUIDs into site.env) -> build images (digests into
# site.env) -> re-render -> runner VM (+ nftables) -> repo settings -> prek + agent gate
```

**B. Reproduce the lab:** you need x86-64 with `/dev/kvm` accessible to your user and Docker. About 10.5 GB of RAM
goes to the three VMs.

```bash
docker build -t cicd-vmlab:1 lab/vmlab
mkdir -p lab/state/img && (cd lab/state/img && curl -fsSLO https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img)
docker run -d --rm --name cicd-vmlab --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  --sysctl net.ipv4.ip_forward=1 -v "$PWD/lab/state":/lab cicd-vmlab:1
docker exec cicd-vmlab vmlab up forge lan 10 3072 2 30
docker exec cicd-vmlab vmlab up runner runner 20 6144 4 40
docker exec cicd-vmlab vmlab up target lan 30 1280 1 15
# then follow phase-3/deep-dive.md §3.1 (each step names the script in lab/scripts/ and the evidence it produced)
```

## What was verified (details: `phase-4/synthesis.md`)

| Area | Result |
|---|---|
| Render all 4 profiles; `nft -c`, `caddy validate`, TOML, actionlint, shellcheck | VERIFIED |
| Forge (Postgres and SQLite) healthy; allow-list returns 403 to outsiders; registration off; sign-in required | VERIFIED |
| Both runner lanes registered via `forgejo-cli actions register` (IaC); `runs-on` routing; ci lane can't reach the deploy dockerd | VERIFIED |
| Egress from job containers, both lanes, 12/12 probes; nftables ordered before Docker's rules | VERIFIED |
| `actions/cache` v4.3.0, v5.1.0 and v6.1.0 hit the runner's LAN cache; CI cold 5m15s, warm 1m42s | VERIFIED |
| ci-base/deploy-base pushed with a `write:package`-only bot PAT, digest-pinned; the automatic token is denied (401) | VERIFIED |
| Tier 1: merge → push by digest → Kamal deploy; failed `/up` keeps the old version (963/963 requests OK); rollback | VERIFIED |
| Tier 2: promote refuses a non-allow-listed app and a SHA without green CI, and deploys a valid one; deploy runner scoped to the deploy repo | VERIFIED |
| Branch protection blocks a red PR, direct pushes and force pushes; prek L1/L2; agent gate in a real Claude Code session | VERIFIED |
| Idle RAM per component, job start latency (~2.4 s to first step), CI and release wall times | MEASURED |

18 template bugs were found on Linux and fixed in the templates, never in rendered output (`phase-3/deep-dive.md`
§3.2). Examples:
- Docker 29 needs the private CA in the daemon's system trust store; `certs.d` alone isn't enough.
- The runner image runs as uid 1000.
- dind needs a healthcheck.
- The DNS egress rule let public resolvers through.
- Kamal needs a `service` label on the image.
- `promote.yml` checked the combined status, not the CI context.

## NOT RUN

| Item | Why |
|---|---|
| GitHub hybrid lane (`gh-runner@`, JIT launcher, GARM, ARC), GitHub push-mirror | Out of scope: needs a GitHub App/org and tokens |
| Alternative B (Woodpecker + Cloudflare tunnel) | Out of scope: no public exposure |
| Advisory LLM-review job | Out of scope: the nftables exception stays templated |
| Gitea swap-in comparison | Optional; not done |
| TLS via DNS-01 ACME or Tailscale certs | Only Caddy `tls internal` was exercised |
| Runner capacity > 1, `upload-artifact@v4`, `permissions:`/`continue-on-error`, concurrency semantics | Not exercised (1 ci slot) |
| osv-scanner / semgrep / syft / grype tasks of `repo-template/Taskfile.yml` | The verification app's contract doesn't call them (BuildKit's syft scanner did produce the SBOM attestation) |
| Backups, scheduled (L5) jobs, per-job VMs | Backlog |

## Left out of this repository (safety)

- The VM disks and the lab's generated keys, tokens, passwords and Caddy CA (`lab/state/`): regenerate them.
  Every secret in the lab was created inside the VMs and is never printed in the evidence.
- Runner UUIDs in `lab/site.lab.env` and the logs are replaced with placeholders. (A UUID encodes the identifier
  half of the runner secret.)
- The underlying Mac research notes and the private brief.
- Host-identifying details of the machine the lab ran on.

The tree was scanned before the first push with gitleaks 8.30.1 and with exact-match greps for every real lab secret,
host name and user name. The only remaining gitleaks findings are false positives:
- cache keys (`go-<sha256 of go.sum>`);
- the upstream example token in Forgejo's default runner config;
- `curl -u "user:$(cat file)"` patterns that contain no literal value.

Also note: `lab/scripts/prek-test.sh` builds its fake key fixture at runtime. The run captured in
`proof-linux/q10-gates/prek-l1-l2.txt` used an earlier, equally fake inline fixture.

## License

MIT (see `LICENSE`). Third-party images and tools keep their own licences.
