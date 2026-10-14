#!/usr/bin/env bash
# detect-host.sh — READ-ONLY host inventory for the CI/CD blueprint. Suggests a hardware profile.
# Changes nothing: no sudo, no installs, no writes outside stdout (and --env FILE if you ask for it).
# Prints no hostname, IP address or user name, so the output is safe to paste into a public issue.
#
#   ./detect-host.sh                 human-readable report + suggested profile
#   ./detect-host.sh --env out.env   also write HOST_* facts that `render.py --host out.env` uses for the
#                                    co-tenant-aware budget (what is already running is subtracted)
#
# Profile floors (see profiles/*.env, all measured against FREE capacity once co-tenants are counted):
#   large  32 threads / 64 GB / 2000 GB     medium 16 / 32 / 1000     small 8 / 16 / 512
#   shared-verify 6 free threads / 10 GB available RAM / 100 GB free disk (a box that already runs other things)
set -uo pipefail
envout=""
[ "${1:-}" = "--env" ] && envout="${2:?--env needs a file}"

threads=$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN)
mem_total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
mem_avail_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
swap_used_kb=$(awk '/^SwapTotal:/{t=$2} /^SwapFree:/{f=$2} END{print t-f}' /proc/meminfo)
gb() { awk -v k="$1" 'BEGIN{printf "%.1f", k/1048576}'; }
mem_total=$(gb "$mem_total_kb"); mem_avail=$(gb "$mem_avail_kb"); swap_used=$(gb "$swap_used_kb")
# RAM already committed to other workloads = total - available (page cache counts as available)
cotenant_ram=$(awk -v t="$mem_total_kb" -v a="$mem_avail_kb" 'BEGIN{printf "%.1f", (t-a)/1048576}')
datadir="${DATA_DIR:-$HOME}"
disk_free=$(df -Pk "$datadir" | awk 'NR==2{printf "%.0f", $4/1048576}')
disk_total=$(df -Pk "$datadir" | awk 'NR==2{printf "%.0f", $2/1048576}')
load1=$(awk '{print $1}' /proc/loadavg)
busy_threads=$(awk -v l="$load1" 'BEGIN{printf "%d", l+0.999}')
free_threads=$((threads - busy_threads)); [ "$free_threads" -lt 0 ] && free_threads=0
arch=$(uname -m)
virt=none
grep -qw vmx /proc/cpuinfo && virt=VT-x
grep -qw svm /proc/cpuinfo && virt=AMD-V
kvm=absent
if [ -e /dev/kvm ]; then kvm=present; [ -r /dev/kvm ] && [ -w /dev/kvm ] && kvm="present+usable-by-this-user"; fi
docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "none/not-accessible")
nft_backend=$( (iptables --version 2>/dev/null || echo "iptables: absent") | sed 's/^iptables //')
vmtools=""
for t in multipass incus lxc virsh qemu-system-x86_64 vagrant; do command -v "$t" >/dev/null 2>&1 && vmtools="$vmtools $t"; done
vmtools="${vmtools# }"; [ -z "$vmtools" ] && vmtools="none"
os=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"); kernel=$(uname -r)

# co-tenant services this blueprint must never disturb (names only)
cotenants=""
for unit in ollama docker tailscaled; do
  systemctl is-active --quiet "$unit" 2>/dev/null && cotenants="$cotenants $unit"
done
nctr=$(docker ps -q 2>/dev/null | wc -l)
[ "$nctr" -gt 0 ] && cotenants="$cotenants docker-containers:$nctr"
cotenants="${cotenants# }"
busy_ports=""
for p in 443 2222 3000 8443 8446 3300 9090 9091; do
  ss -Htln "sport = :$p" 2>/dev/null | grep -q . && busy_ports="$busy_ports $p"
done
busy_ports="${busy_ports# }"; [ -z "$busy_ports" ] && busy_ports="none"

# profile suggestion: compare FREE capacity (not totals) against each profile floor
suggest=none
fits() { awk -v t="$free_threads" -v r="$mem_avail" -v d="$disk_free" -v T="$1" -v R="$2" -v D="$3" \
          'BEGIN{exit !(t>=T && r>=R && d>=D)}'; }
if [ "$arch" != x86_64 ] || [ "$virt" = none ]; then suggest="none (needs x86-64 with VT-x/AMD-V)"
elif fits 32 64 2000; then suggest=large
elif fits 16 32 1000; then suggest=medium
elif fits 8 16 512; then suggest=small
elif fits 6 10 100; then suggest=shared-verify
fi
# a box whose TOTALS meet a profile but whose free capacity does not is a shared box
nominal=none
awk -v t="$threads" -v r="$mem_total" 'BEGIN{exit !(t>=16 && r>=30)}' && nominal=medium
[ "$nominal" = none ] && awk -v t="$threads" -v r="$mem_total" 'BEGIN{exit !(t>=8 && r>=15)}' && nominal=small

cat <<EOF
== detect-host (read-only) ==
os            : $os, kernel $kernel, arch $arch
cpu threads   : $threads total, load1 $load1 -> ~$free_threads free
virtualization: $virt, /dev/kvm $kvm
ram           : $mem_total GB total, $mem_avail GB available, co-tenant use ~$cotenant_ram GB, swap used $swap_used GB
disk ($([ "$datadir" = "$HOME" ] && echo '$HOME' || echo "$datadir")) : $disk_free GB free of $disk_total GB
docker        : $docker_ver   (runner v13 needs >= 25 inside the runner VM, not here)
iptables      : $nft_backend
vm tooling    : $vmtools
co-tenants    : ${cotenants:-none}
busy ports    : $busy_ports   (blueprint defaults: 443 caddy, 2222 forgejo ssh)
nominal size  : $nominal (by totals)
SUGGESTED     : $suggest (by FREE capacity after co-tenants)
EOF
if [ "$vmtools" = none ]; then
  echo "note: no VM tooling installed; the runner VM needs one (multipass, incus, libvirt) or a QEMU-in-container lab."
fi

if [ -n "$envout" ]; then
  cat > "$envout" <<EOF
# written by detect-host.sh; facts only, no names or addresses
HOST_THREADS=$threads
HOST_FREE_THREADS=$free_threads
HOST_RAM_GB=$mem_total
HOST_AVAIL_RAM_GB=$mem_avail
HOST_COTENANT_RAM_GB=$cotenant_ram
HOST_FREE_DISK_GB=$disk_free
HOST_KVM=$kvm
HOST_DOCKER=$docker_ver
HOST_SUGGESTED_PROFILE=$suggest
EOF
  echo "wrote $envout"
fi
