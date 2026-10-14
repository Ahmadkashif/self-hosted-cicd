#!/usr/bin/env python3
"""Render the CI/CD blueprint templates for one hardware profile and check the resource budget.

Usage:  python3 render.py <profile> [--site site.env] [--out build] [--host host.env]
  <profile> = any profiles/<name>.env (small, medium, large, shared-verify, ...)
  --host    = output of `detect-host.sh --env host.env`: also check against FREE capacity (co-tenants subtracted)
Reads profiles/<profile>.env + site.env (falls back to site.env.example), derives per-lane limits, refuses
budgets that do not fit the profile's documented minimum host, renders every *.tmpl to build/<profile>/,
writes forge-host.env / runner-vm.env for `docker compose --env-file`, and syntax-checks YAML/JSON.
Pure stdlib (PyYAML used for YAML checks only if installed). Never touches Docker or the network.
"""
import argparse, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent
VAR = re.compile(r"\$\{([A-Z0-9_]+)\}")              # only ${NAME}; bare $NAME (e.g. $CREDENTIALS_DIRECTORY) is left alone
COMPOSE_VAR = re.compile(r"\$\{([A-Z0-9_]+)(:-[^}]*)?\}")

def load_env(path):
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env

def mem_to_gb(s):
    s = s.strip().lower()
    return float(s[:-1]) / 1024 if s.endswith("m") else float(s.rstrip("g"))

def derive(env):
    f = lambda k: float(env[k])
    lanes = {}
    for lane in ("CI", "DEPLOY", "GITHUB"):
        slots, cpus, mem = f(f"{lane}_SLOTS"), f(f"{lane}_SLOT_CPUS"), f(f"{lane}_SLOT_MEM_GB")
        lanes[lane] = (slots, cpus, mem)
        env[f"DIND_{lane}_MEM_LIMIT"] = f"{int(max(slots * mem, 0.5) * 1024 + 512)}m"
        env[f"DIND_{lane}_CPUS"] = str(max(slots * cpus, 1))
    env["CI_SLOT_MEM_BYTES"] = str(int(f("CI_SLOT_MEM_GB") * 1024 ** 3))
    env["DEPLOY_TARGETS_NFT"] = ", ".join(env["DEPLOY_TARGETS"].split())
    return lanes

def budget(env, lanes, host=None):
    """Check the profile against its own floors and, with --host (detect-host.sh output), against FREE capacity.

    FORGE_PLACEMENT=host (default, S/M/L): forge services + runner VM + apps share one dedicated host.
    FORGE_PLACEMENT=vm (shared-verify): forge services must fit FORGE_VM_RAM_GB; the host pays for whole VMs.
    With --host the co-tenant load (HOST_COTENANT_RAM_GB) is subtracted: everything must fit what is AVAILABLE.
    """
    f = lambda k, d=None: float(env[k]) if k in env else float(d)
    problems, rows = [], []
    vm_need = 1.0 + sum(s * m for s, _, m in lanes.values())
    vm_cpu = sum(s * c for s, c, _ in lanes.values())
    rows.append(("runner VM RAM needed (1 GB base + slots)", vm_need, f("RUNNER_VM_RAM_GB")))
    if vm_need > f("RUNNER_VM_RAM_GB"):
        problems.append(f"runner VM RAM {f('RUNNER_VM_RAM_GB')} GB < needed {vm_need:.2f} GB")
    if vm_cpu > f("RUNNER_VM_VCPUS") * 1.5:
        problems.append(f"slot vCPUs {vm_cpu:.0f} > 1.5x runner VM vCPUs {f('RUNNER_VM_VCPUS'):.0f}")
    if f("RUNNER_VM_VCPUS") > f("HOST_MIN_THREADS") - 2:
        problems.append("runner VM vCPUs leave < 2 threads for the host")
    komodo = 1.0 if env.get("CD_TOOL") == "komodo" else 0.0
    forge_services = (f("FORGEJO_RAM_GB") + f("POSTGRES_RAM_GB") + mem_to_gb(env["REGISTRY_MEM_LIMIT"])
                      + f("EDGE_RAM_GB"))
    placement = env.get("FORGE_PLACEMENT", "host")
    if placement == "vm":
        forge_vm_need = 0.75 + forge_services + 0.5          # guest OS + services + outer dockerd/page cache
        rows.append(("forge VM RAM needed (OS+forge+db+mirror+edge+docker)", forge_vm_need, f("FORGE_VM_RAM_GB")))
        if forge_vm_need > f("FORGE_VM_RAM_GB"):
            problems.append(f"forge VM RAM {f('FORGE_VM_RAM_GB')} GB < needed {forge_vm_need:.2f} GB")
        host_need = (f("FORGE_VM_RAM_GB") + f("RUNNER_VM_RAM_GB") + f("TARGET_VM_RAM_GB", 0)
                     + f("APPS_RAM_GB") + komodo)
        label = "host RAM needed (forge VM + runner VM + target VM + apps)"
    elif placement == "host":
        host_need = 1.0 + forge_services + f("RUNNER_VM_RAM_GB") + f("APPS_RAM_GB") + komodo
        label = "host RAM needed (OS+forge+db+mirror+edge+VM+apps+CD)"
    else:
        sys.exit(f"ERROR FORGE_PLACEMENT={placement!r} (host|vm)")
    rows.append((label, host_need, f("HOST_MIN_RAM_GB")))
    if host_need > f("HOST_MIN_RAM_GB"):
        problems.append(f"host RAM {f('HOST_MIN_RAM_GB')} GB < needed {host_need:.2f} GB")
    elif host_need > 0.9 * f("HOST_MIN_RAM_GB"):
        print(f"WARN: host RAM headroom below 10% ({host_need:.2f}/{f('HOST_MIN_RAM_GB')} GB)")
    disk_need = (20 + 100 + f("RUNNER_VM_DISK_GB") + 50) if placement == "host" else \
                (f("FORGE_VM_DISK_GB", 30) + f("RUNNER_VM_DISK_GB") + 15 + 5)
    rows.append(("host disk needed (forge/packages + runner VM + mirror [+ target])", disk_need, f("HOST_MIN_DISK_GB")))
    if disk_need > f("HOST_MIN_DISK_GB"):
        problems.append("disk budget exceeds profile minimum")
    if host:                                                  # co-tenant-aware: compare with what is FREE now
        h = lambda k: float(host[k])
        rows.append(("  vs. RAM available now (detect-host: total - co-tenants)", host_need, h("HOST_AVAIL_RAM_GB")))
        if host_need > h("HOST_AVAIL_RAM_GB") - 1.0:          # keep 1 GB for the co-tenants to breathe
            problems.append(f"needs {host_need:.2f} GB but only {h('HOST_AVAIL_RAM_GB')} GB is available "
                            f"({h('HOST_COTENANT_RAM_GB')} GB used by co-tenants; 1 GB reserve)")
        vcpus = f("RUNNER_VM_VCPUS") + f("FORGE_VM_VCPUS", 0) + f("TARGET_VM_VCPUS", 0)
        rows.append(("  vs. free threads now (detect-host: threads - load)", vcpus, h("HOST_FREE_THREADS")))
        if f("RUNNER_VM_VCPUS") > h("HOST_FREE_THREADS") - 2:
            problems.append(f"runner VM vCPUs {f('RUNNER_VM_VCPUS'):.0f} leave < 2 free threads "
                            f"({h('HOST_FREE_THREADS'):.0f} free now)")
        rows.append(("  vs. free disk now", disk_need, h("HOST_FREE_DISK_GB")))
        if disk_need > h("HOST_FREE_DISK_GB"):
            problems.append("not enough free disk on the host")
        if not str(host.get("HOST_KVM", "")).startswith("present"):
            problems.append("no /dev/kvm: the runner VM needs hardware virtualization")
    return rows, problems

def render(env, out):
    produced = []
    for tmpl in sorted(ROOT.rglob("*.tmpl")):
        if out in tmpl.parents:
            continue
        text = tmpl.read_text()
        missing = sorted({m for m in VAR.findall(text) if m not in env})
        if missing:
            sys.exit(f"ERROR {tmpl.relative_to(ROOT)}: unknown variables {missing}")
        target = out / tmpl.name[:-len(".tmpl")]
        target.write_text(VAR.sub(lambda m: env[m.group(1)], text))
        produced.append(target)
    return produced

def check_syntax(paths):
    try:
        import yaml
    except ImportError:
        yaml = None
        print("note: PyYAML not installed; YAML files not parsed")
    bad = 0
    for p in paths:
        try:
            if p.suffix == ".json" or p.name.endswith(".json.example"):
                json.loads(p.read_text())
            elif yaml and p.suffix in (".yml", ".yaml"):
                list(yaml.safe_load_all(p.read_text()))
        except Exception as e:  # noqa: BLE001
            bad += 1
            print(f"SYNTAX ERROR {p}: {e}")
    return bad

def main():
    ap = argparse.ArgumentParser()
    profiles = sorted(p.stem for p in (ROOT / "profiles").glob("*.env"))
    ap.add_argument("profile", choices=profiles)
    ap.add_argument("--host", default=None, help="detect-host.sh --env output: co-tenant-aware budget")
    ap.add_argument("--site", default=None)
    ap.add_argument("--out", default="build")
    a = ap.parse_args()
    site = pathlib.Path(a.site) if a.site else (ROOT / "site.env" if (ROOT / "site.env").exists() else ROOT / "site.env.example")
    env = {**load_env(ROOT / "profiles" / f"{a.profile}.env"), **load_env(site)}
    lanes = derive(env)
    host = load_env(pathlib.Path(a.host)) if a.host else None
    rows, problems = budget(env, lanes, host)
    print(f"profile={a.profile} site={site.name}")
    for name, need, have in rows:
        print(f"  {name:<58} {need:7.2f} / {have:7.2f}")
    if problems:
        sys.exit("BUDGET FAIL:\n  - " + "\n  - ".join(problems))
    base = pathlib.Path(a.out)
    out = (base if base.is_absolute() else ROOT / base) / a.profile
    out.mkdir(parents=True, exist_ok=True)
    produced = render(env, out)
    envfile = "\n".join(f"{k}={v}" for k, v in sorted(env.items())) + "\n"
    for name in ("forge-host.env", "runner-vm.env"):
        (out / name).write_text(envfile)
    # every ${VAR} used by the compose files must be defined (or have a :-default)
    for compose in sorted(ROOT.rglob("compose.yaml")):
        if out in compose.parents:
            continue
        undefined = sorted({n for n, d in COMPOSE_VAR.findall(compose.read_text()) if not d and n not in env})
        if undefined:
            print(f"note: {compose.relative_to(ROOT)} expects from a secrets env file: {undefined}")
    others = [p for p in ROOT.rglob("*") if p.is_file() and out not in p.parents and p.suffix in (".yml", ".yaml", ".json")
              or p.name.endswith(".json.example")]
    bad = check_syntax(produced + others)
    print(f"rendered {len(produced)} files -> {out}; syntax errors: {bad}")
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
