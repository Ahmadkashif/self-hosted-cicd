# Phase 1: Scoping (2026-10-14)

## Inputs read
`brief.md` (incl. the 2026-10-14 "Registry commitment" addendum: a working PoC published as a public MIT repo on
`Ahmadkashif`), `mac-source/findings.md`, `mac-source/phase-5/README.md` + all templates, `mac-source/phase-6/synthesis.md`,
`related/ubuntu-web-deploy-platform/.../forgejo-deploy.yml.tmpl`, and the sibling topic `../ubuntu-deploy-platform/`
(for its proven no-host-change VM lab pattern).

## Host inventory (read-only; `proof-linux/q01-host-fit/detect-host.txt`)
- x86-64, 16 threads, VT-x, `/dev/kvm` present and usable by the operator (user ACL), 31.1 GB RAM (18.8 GB
  available at the time; ~12.3 GB used by co-tenants, 4.1 GB swap in use), ~800 GB free disk, Ubuntu 24.04.
- Docker 29.8.1 (iptables-nft). Co-tenants at the time: `ollama.service`, one unrelated container. The LLM gateway,
  observability stacks and Tailscale serve were not listening at the time (ports 443/8443/8446/3300/9090/9091 free),
  but the brief says they exist, so they are treated as present: nothing binds those ports.
- **No VM tooling installed** (multipass/LXD/Incus/libvirt/qemu absent). `sudo` is not used (rule).

## Decision: how to get disposable VMs without changing the host
Installing VM tooling needs sudo and approval (not available mid-run). The facility already has a precedent
(`../ubuntu-deploy-platform`, phase-1 host inventory): **real KVM VMs run as QEMU processes inside a dedicated
container**. Here: image `cicd-vmlab:1` (built from `lab/vmlab/Dockerfile`), started with
`docker run -d --rm --name cicd-vmlab --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN --sysctl net.ipv4.ip_forward=1 -v lab/state:/lab`.
- Not `--privileged`, no published ports, no host networking, default bridge (no new Docker network), unique name, `--rm`.
- `NET_ADMIN` and the sysctl apply only to the container's own network namespace: the lab bridges, NAT, dnsmasq and
  the "LAN service" probes live there. No host bridge, sysctl, firewall, daemon config, unit or package changes.
- Everything risky in the brief (privileged dind, nftables, forge compose publishing :443/:2222) runs **inside the VMs**.
- This is a judgment call against the orchestrator's "short-lived validation container" wording (the container is
  long-lived and has a device + NET_ADMIN). It is recorded in STATUS.md under live-host changes so the user can veto it;
  teardown removes it completely.

## Lab topology (all private ranges on purpose, so the RFC1918 refusal is tested against real targets)
| Segment | Range | Members |
|---|---|---|
| "home LAN" (labbr0) | 10.77.0.0/24 | gateway/resolver .1 (dnsmasq), forge VM .10 (3 GB, 2 vCPU), deploy-target VM .30 (1.25 GB, 1 vCPU), outsider probe source .99, LAN "NAS" probe .1:8080 |
| "runner VLAN" (labbr1) | 10.78.0.0/24 | gateway/resolver .1 (`RUNNER_DNS`), runner VM .20 (6 GB, 4 vCPU) |
| CGNAT probe | 100.64.0.1:8080 | dummy interface in the lab container |
DNS: `git.lab.test`/`mirror.lab.test` → forge, `app.lab.test` → target. VMs: Ubuntu 24.04 cloud image (sha256-verified).

## Profile choice (Q1)
By totals the box is "medium" (16 threads / 31 GB); by FREE capacity `detect-host.sh` suggests "small". Neither
models a box whose forge must not touch the host's Docker and ports, so a `shared-verify` profile was added:
everything in VMs (forge VM 3 GB, runner VM 6 GB with 1 ci slot 2 vCPU/3 GB + 1 deploy slot 1 vCPU/2 GB, target VM
1.25 GB), floors stated as FREE capacity (≥ 6 free threads, ≥ 12 GB available, ≥ 100 GB disk), and a co-tenant-aware
budget in `render.py --host host.env`.

## Classification of questions / done-criteria steps
| Item | Class |
|---|---|
| Q1 host fit, Q2 render + machine checks | runnable now (Q2 nft check inside a VM) |
| Q3–Q9, Q11, done steps 1–7 | VM lab (runnable: VM tooling-in-container) |
| Q10 prek L1/L2 | VM lab (dev container in forge VM) |
| Q10 agent gate / done step 8 | real Claude Code session on the host against a scratch repo (no VM: copying Claude credentials into a VM would transfer a secret) |
| Q12 Gitea swap-in | optional; NOT RUN (time) |
| GitHub lane, Woodpecker, LLM-review job | out of scope: NOT RUN / reference only |

## Live-host approval list
None needed for this round (see STATUS.md for the commands the user would run to install real VM tooling instead
of the lab container, should they prefer it).
